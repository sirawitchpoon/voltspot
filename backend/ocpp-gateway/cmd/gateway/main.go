// Command gateway is the Voltspot OCPP-J 1.6 gateway. Hosts persistent
// WebSocket connections from chargers, exposes a small REST API for
// the iOS app to issue remote start/stop, and writes session +
// connector state into Firestore.
//
// Designed to run on Google Cloud Run with min-instances=1 + CPU
// always allocated — chargers expect their WebSocket to stay open
// for hours, which scale-to-zero would break.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/option"

	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/auth"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/firestore"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/server"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/transactions"
)

// config bundles environment-driven settings. Read once at startup
// so a config typo fails fast rather than producing silent fallbacks.
type config struct {
	port               string
	firebaseProjectID  string
	credentialsPath    string // optional — Cloud Run ADC handles this
	corsAllowedOrigins []string
	idleAfter          time.Duration
	idleSweepInterval  time.Duration
	callTimeout        time.Duration
	restCallTimeout    time.Duration
	shutdownTimeout    time.Duration
	pendingStartTTL    time.Duration
}

func loadConfig() (config, error) {
	c := config{
		port:               getEnv("PORT", "8080"),
		firebaseProjectID:  os.Getenv("FIREBASE_PROJECT_ID"),
		credentialsPath:    os.Getenv("GOOGLE_APPLICATION_CREDENTIALS"),
		corsAllowedOrigins: splitEnv("CORS_ALLOWED_ORIGINS"),
		idleAfter:          parseDuration("CHARGER_IDLE_AFTER", 10*time.Minute),
		idleSweepInterval:  parseDuration("IDLE_SWEEP_INTERVAL", 2*time.Minute),
		callTimeout:        parseDuration("CALL_TIMEOUT", 30*time.Second),
		restCallTimeout:    parseDuration("REST_CALL_TIMEOUT", 10*time.Second),
		shutdownTimeout:    parseDuration("SHUTDOWN_TIMEOUT", 25*time.Second),
		pendingStartTTL:    parseDuration("PENDING_START_TTL", 5*time.Minute),
	}
	if c.firebaseProjectID == "" {
		return c, errors.New("FIREBASE_PROJECT_ID env var is required")
	}
	return c, nil
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		// Level=Info matches Cloud Run's "log levels" filter — debug
		// info available via LOG_LEVEL=debug for one-off troubleshooting.
		Level: parseLogLevel(),
	}))
	slog.SetDefault(logger)

	cfg, err := loadConfig()
	if err != nil {
		logger.Error("config", slog.String("err", err.Error()))
		os.Exit(2)
	}

	rootCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if err := run(rootCtx, logger, cfg); err != nil {
		logger.Error("gateway exited", slog.String("err", err.Error()))
		os.Exit(1)
	}
}

func run(ctx context.Context, logger *slog.Logger, cfg config) error {
	// ─── Firebase + Firestore ──────────────────────────────────────
	app, err := newFirebaseApp(ctx, cfg)
	if err != nil {
		return fmt.Errorf("init firebase: %w", err)
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		return fmt.Errorf("init auth: %w", err)
	}
	fsClient, err := newFirestoreClient(ctx, cfg)
	if err != nil {
		return fmt.Errorf("init firestore: %w", err)
	}
	defer func() { _ = fsClient.Close() }()
	fsWriter := firestore.New(fsClient)

	// Seed the transaction allocator so Gateway restarts don't reuse
	// existing transaction ids.
	floor, err := fsWriter.MaxTransactionID(ctx)
	if err != nil {
		// Continue with floor=0 — collisions are unlikely on a fresh
		// project and a startup-time read failure shouldn't crash a
		// healthy gateway.
		logger.Warn("transaction id floor lookup failed; defaulting to 0",
			slog.String("err", err.Error()))
		floor = 0
	}
	logger.Info("transaction allocator seeded", slog.Int64("floor", floor))
	txAllocator := transactions.New(floor)

	// ─── Server stack ──────────────────────────────────────────────
	hub := server.NewHub()
	pendingStarts := server.NewPendingStarts(cfg.pendingStartTTL)
	delegate := server.NewAppDelegate(
		logger,
		fsWriter,
		&server.FirestoreTariffProvider{Writer: fsWriter},
		txAllocator,
		pendingStarts,
	)

	hub.StartIdleSweeper(ctx, cfg.idleSweepInterval, cfg.idleAfter)
	startPendingStartsSweeper(ctx, pendingStarts, cfg.idleSweepInterval)

	wsHandler := &server.WSHandler{
		Hub:            hub,
		Delegate:       delegate,
		Logger:         logger,
		CallTimeout:    cfg.callTimeout,
		AllowedOrigins: cfg.corsAllowedOrigins,
	}

	restHandler := &server.RESTHandler{
		Hub:           hub,
		Logger:        logger,
		Firestore:     fsWriter,
		PendingStarts: pendingStarts,
		CallTimeout:   cfg.restCallTimeout,
	}

	health := &server.HealthHandler{Hub: hub}

	mux := http.NewServeMux()
	mux.Handle("/ocpp/", wsHandler)
	mux.HandleFunc("GET /healthz", health.Healthz)
	mux.HandleFunc("GET /readyz", health.Readyz)
	// Auth-gated REST routes
	mux.Handle("/api/", auth.Middleware(authClient)(restHandler.Routes()))

	httpServer := &http.Server{
		Addr:              ":" + cfg.port,
		Handler:           withRequestID(withRecover(logger, mux)),
		ReadHeaderTimeout: 10 * time.Second,
		// Keep-alive long enough for the WS handshake; per-conn
		// timeouts are managed inside the WS handler.
		IdleTimeout: 120 * time.Second,
	}

	health.MarkReady()
	logger.Info("listening", slog.String("addr", httpServer.Addr))

	serverErr := make(chan error, 1)
	go func() {
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
		close(serverErr)
	}()

	// ─── Wait for shutdown signal or fatal server error ────────────
	select {
	case <-ctx.Done():
		logger.Info("shutdown signal received")
	case err, ok := <-serverErr:
		if ok && err != nil {
			return fmt.Errorf("http server: %w", err)
		}
	}

	// ─── Graceful shutdown ─────────────────────────────────────────
	health.MarkNotReady()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.shutdownTimeout)
	defer cancel()

	// Stop accepting new HTTP traffic — existing requests get the
	// remaining shutdown budget to finish.
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		logger.Warn("http shutdown error", slog.String("err", err.Error()))
	}
	// Drain WebSocket connections.
	hub.Close()
	logger.Info("shutdown complete")
	return nil
}

// startPendingStartsSweeper runs a periodic eviction of expired
// pending-starts entries so the in-memory map doesn't grow with
// abandoned remote-start attempts. Sweeps at the same cadence as the
// hub's idle sweeper because both are reasonably bounded by the same
// "things that should have happened by now" interval.
func startPendingStartsSweeper(ctx context.Context, p *server.PendingStarts, interval time.Duration) {
	if interval <= 0 {
		interval = 2 * time.Minute
	}
	go func() {
		t := time.NewTicker(interval)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				p.EvictExpired()
			}
		}
	}()
}

func newFirebaseApp(ctx context.Context, cfg config) (*firebase.App, error) {
	conf := &firebase.Config{ProjectID: cfg.firebaseProjectID}
	if cfg.credentialsPath != "" {
		return firebase.NewApp(ctx, conf, option.WithCredentialsFile(cfg.credentialsPath))
	}
	// On Cloud Run, ADC picks up the runtime service account.
	return firebase.NewApp(ctx, conf)
}

func newFirestoreClient(ctx context.Context, cfg config) (*cloudfirestore.Client, error) {
	if cfg.credentialsPath != "" {
		return cloudfirestore.NewClient(ctx, cfg.firebaseProjectID, option.WithCredentialsFile(cfg.credentialsPath))
	}
	return cloudfirestore.NewClient(ctx, cfg.firebaseProjectID)
}

// ─── env helpers ──────────────────────────────────────────────────────

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func splitEnv(key string) []string {
	v := os.Getenv(key)
	if v == "" {
		return nil
	}
	parts := strings.Split(v, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if s := strings.TrimSpace(p); s != "" {
			out = append(out, s)
		}
	}
	return out
}

func parseDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return fallback
	}
	return d
}

func parseLogLevel() slog.Level {
	switch strings.ToLower(os.Getenv("LOG_LEVEL")) {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	}
	return slog.LevelInfo
}
