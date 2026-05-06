package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"runtime/debug"
)

// requestIDKey is the context-key type for the per-request id we
// stamp on inbound HTTP requests. Used by access-log entries so the
// iOS team can correlate failing requests with Gateway logs.
type requestIDKey struct{}

// withRequestID assigns each inbound request a short hex id. If the
// caller already sent X-Request-Id (e.g. from an upstream proxy), use
// that — keeps cross-service tracing stable.
func withRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-Id")
		if id == "" {
			id = newRequestID()
		}
		w.Header().Set("X-Request-Id", id)
		ctx := context.WithValue(r.Context(), requestIDKey{}, id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// requestIDFromContext returns the request id for logging. Empty
// string if the middleware wasn't applied — defensive default keeps
// log lines short instead of panicking.
func requestIDFromContext(ctx context.Context) string {
	if v, ok := ctx.Value(requestIDKey{}).(string); ok {
		return v
	}
	return ""
}

func newRequestID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "req-fallback"
	}
	return hex.EncodeToString(b[:])
}

// withRecover catches panics from inside the handler chain so a
// single bug doesn't crash the whole Cloud Run instance. Logs the
// stack trace + request id then writes a 500.
func withRecover(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rv := recover(); rv != nil {
				logger.Error("handler panic",
					slog.Any("panic", rv),
					slog.String("requestId", requestIDFromContext(r.Context())),
					slog.String("path", r.URL.Path),
					slog.String("stack", string(debug.Stack())))
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusInternalServerError)
				_, _ = w.Write([]byte(`{"error":"internal error"}`))
			}
		}()
		next.ServeHTTP(w, r)
	})
}
