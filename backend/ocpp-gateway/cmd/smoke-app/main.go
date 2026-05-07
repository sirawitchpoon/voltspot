// Command smoke-app runs an end-to-end smoke test for the iOS app's
// Firebase backend — Auth, Firestore data, and security rules — with
// the same colored PASS/FAIL output style as cmd/smoke (the OCPP
// gateway smoke test). Mirrored on purpose: a single screenshot per
// phase makes a clean slide.
//
// What it verifies (Phase A):
//
//   - Firebase Admin SDK (Auth + Firestore) reach the project
//   - Identity Toolkit Web API key resolves (from plist or env)
//   - Sign-up REST endpoint creates a user and returns an ID token
//   - Admin verifyIDToken accepts the freshly-minted token
//   - Stations collection has ≥6 seeded docs (matches MockStationRepository.allSamples)
//   - Each station's tariff fields are integers (the satang invariant)
//   - Each station's geohash is 9 chars and starts with the Thailand
//     prefix `w` (sanity check on the seeder + decoder)
//   - With user A's ID token: stations read succeeds (signed-in users
//     have read access per deploy/firestore.rules)
//   - Without any token: stations read returns 401/403 (rule blocks
//     anonymous access)
//   - User A can write their own /users/{uidA} doc
//   - User A CANNOT write /users/{uidB} (cross-user rule enforced)
//
// Usage:
//
//	go run ./cmd/smoke-app                       # auto-resolves API key from plist
//	go run ./cmd/smoke-app -api-key XXXXXXX      # explicit key
//	go run ./cmd/smoke-app -no-cleanup           # leave test users behind for inspection
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	firebaseauth "firebase.google.com/go/v4/auth"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
)

var (
	flagProjectID = flag.String("project",
		envOr("FIREBASE_PROJECT_ID", ""),
		"Firebase project ID — required")
	flagSAPath = flag.String("service-account",
		envOr("GOOGLE_APPLICATION_CREDENTIALS", ""),
		"Path to service-account JSON. Empty = ADC.")
	flagAPIKey = flag.String("api-key",
		envOr("VOLTSPOT_FIREBASE_API_KEY", ""),
		"Firebase Web API key. Empty = read from -plist.")
	flagPlistPath = flag.String("plist",
		"../../Voltspot/Resources/GoogleService-Info.plist",
		"Path to GoogleService-Info.plist (used when -api-key is empty)")
	flagCleanup = flag.Bool("cleanup",
		true,
		"Delete test users + /users docs after run")
	flagTimeout = flag.Duration("timeout",
		15*time.Second,
		"Per-step timeout")
)

// ANSI escape codes — same set as cmd/smoke so screenshots line up
// visually when both phases are pasted side by side on a slide.
const (
	cReset = "\033[0m"
	cRed   = "\033[31m"
	cGreen = "\033[32m"
	cCyan  = "\033[36m"
	cBold  = "\033[1m"
	cDim   = "\033[2m"
)

func main() {
	flag.Parse()
	if *flagProjectID == "" {
		exit("smoke-app: set -project or FIREBASE_PROJECT_ID")
	}

	header(fmt.Sprintf("Voltspot Phase A smoke test  ·  project=%s", *flagProjectID))

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	r := newRunner(ctx)
	r.run()

	fmt.Println()
	r.summary()

	if *flagCleanup {
		// Cleanup runs even if some scenarios failed — leftover test
		// users would cause the next run to fail with "email already
		// in use", which would mask a real regression.
		if err := r.cleanup(ctx); err != nil {
			fmt.Printf("%scleanup warning: %s%s\n", cRed, err, cReset)
		}
	}

	if r.failed > 0 {
		os.Exit(1)
	}
}

// ─── Runner (mirrors cmd/smoke for visual parity) ────────────────────

type runner struct {
	ctx context.Context

	apiKey    string
	authAdmin *firebaseauth.Client
	fs        *cloudfirestore.Client

	// Two test users so we can probe cross-user rules.
	userA testUser
	userB testUser

	passed int
	failed int
}

type testUser struct {
	uid     string
	email   string
	idToken string
}

func newRunner(ctx context.Context) *runner {
	stamp := time.Now().UnixNano()
	return &runner{
		ctx: ctx,
		userA: testUser{
			email: fmt.Sprintf("smoke-a-%d@voltspot.test", stamp),
		},
		userB: testUser{
			email: fmt.Sprintf("smoke-b-%d@voltspot.test", stamp),
		},
	}
}

func (r *runner) step(name string, fn func() error) {
	stepCtx, cancel := context.WithTimeout(r.ctx, *flagTimeout)
	defer cancel()

	fmt.Printf("  %s%-58s%s ", cDim, name, cReset)

	type result struct{ err error }
	done := make(chan result, 1)
	go func() {
		done <- result{err: fn()}
	}()

	select {
	case res := <-done:
		if res.err != nil {
			fmt.Printf("%s%sFAIL%s  %s%s%s\n",
				cRed, cBold, cReset, cRed, res.err.Error(), cReset)
			r.failed++
			return
		}
		fmt.Printf("%s%sPASS%s\n", cGreen, cBold, cReset)
		r.passed++
	case <-stepCtx.Done():
		fmt.Printf("%s%sFAIL%s  %stimeout after %s%s\n",
			cRed, cBold, cReset, cRed, flagTimeout.String(), cReset)
		r.failed++
	}
}

func (r *runner) summary() {
	total := r.passed + r.failed
	if r.failed == 0 {
		fmt.Printf("%s%s%d/%d PASSED%s\n", cGreen, cBold, r.passed, total, cReset)
		return
	}
	fmt.Printf("%s%s%d/%d PASSED · %d FAILED%s\n",
		cRed, cBold, r.passed, total, r.failed, cReset)
}

// ─── Phase A scenarios ───────────────────────────────────────────────

func (r *runner) run() {
	r.step("Web API key resolves (plist or -api-key)", r.resolveAPIKey)
	if r.failed > 0 {
		return
	}

	r.step("Firebase Admin SDK connects", r.connectAdmin)
	if r.failed > 0 {
		return
	}

	r.step("Sign up user A via Identity Toolkit", func() error {
		return r.signUp(&r.userA)
	})
	r.step("Sign up user B via Identity Toolkit", func() error {
		return r.signUp(&r.userB)
	})
	r.step("Admin verifyIDToken accepts user A's token", r.verifyTokenA)

	r.step("Stations collection has ≥6 seeded docs", r.stationsCount)
	r.step("Every station tariff is integer satang (no Doubles)", r.stationsTariffIntegrity)
	r.step("Every station has a 9-char Thailand-region geohash", r.stationsGeohashIntegrity)

	r.step("Authenticated read: user A can list /stations", r.userACanReadStations)
	r.step("Anonymous read: /stations returns 401/403", r.anonymousCannotReadStations)

	r.step("User A can write own /users/{uidA}", r.userACanWriteOwnDoc)
	r.step("User A CANNOT write /users/{uidB}", r.userACannotWriteOthersDoc)
}

// ─── Step implementations ────────────────────────────────────────────

func (r *runner) resolveAPIKey() error {
	if *flagAPIKey != "" {
		r.apiKey = *flagAPIKey
		return nil
	}
	plist, err := os.ReadFile(*flagPlistPath)
	if err != nil {
		return fmt.Errorf("read plist %s: %w (or pass -api-key)", *flagPlistPath, err)
	}
	// Tiny regex extractor — full plist parser is overkill for a
	// single key. Format: <key>API_KEY</key><string>VALUE</string>.
	re := regexp.MustCompile(`<key>API_KEY</key>\s*<string>([^<]+)</string>`)
	m := re.FindSubmatch(plist)
	if m == nil {
		return errors.New("API_KEY not found in plist")
	}
	r.apiKey = string(m[1])
	return nil
}

func (r *runner) connectAdmin() error {
	conf := &firebase.Config{ProjectID: *flagProjectID}
	var opts []option.ClientOption
	if *flagSAPath != "" {
		opts = append(opts, option.WithCredentialsFile(*flagSAPath))
	}
	app, err := firebase.NewApp(r.ctx, conf, opts...)
	if err != nil {
		return fmt.Errorf("init firebase app: %w", err)
	}
	auth, err := app.Auth(r.ctx)
	if err != nil {
		return fmt.Errorf("init auth: %w", err)
	}
	fs, err := cloudfirestore.NewClient(r.ctx, *flagProjectID, opts...)
	if err != nil {
		return fmt.Errorf("init firestore: %w", err)
	}
	r.authAdmin = auth
	r.fs = fs
	return nil
}

func (r *runner) signUp(u *testUser) error {
	body, _ := json.Marshal(map[string]any{
		"email":             u.email,
		"password":          "smoke-test-pw-12345",
		"returnSecureToken": true,
	})
	url := fmt.Sprintf(
		"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s",
		r.apiKey,
	)
	req, err := http.NewRequestWithContext(r.ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("identitytoolkit signUp HTTP %d: %s", resp.StatusCode, string(raw))
	}
	var out struct {
		LocalID string `json:"localId"`
		IDToken string `json:"idToken"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return err
	}
	if out.LocalID == "" || out.IDToken == "" {
		return errors.New("signUp response missing localId or idToken")
	}
	u.uid = out.LocalID
	u.idToken = out.IDToken
	return nil
}

func (r *runner) verifyTokenA() error {
	tok, err := r.authAdmin.VerifyIDToken(r.ctx, r.userA.idToken)
	if err != nil {
		return err
	}
	if tok.UID != r.userA.uid {
		return fmt.Errorf("verified UID %s ≠ signUp UID %s", tok.UID, r.userA.uid)
	}
	return nil
}

func (r *runner) stationsCount() error {
	docs, err := r.fs.Collection("stations").Documents(r.ctx).GetAll()
	if err != nil {
		return err
	}
	if len(docs) < 6 {
		return fmt.Errorf("found %d stations, want ≥6 (run scripts/seed-stations.js?)", len(docs))
	}
	return nil
}

func (r *runner) stationsTariffIntegrity() error {
	iter := r.fs.Collection("stations").Documents(r.ctx)
	defer iter.Stop()
	for {
		snap, err := iter.Next()
		if err == iterator.Done {
			return nil
		}
		if err != nil {
			return err
		}
		tariff, ok := snap.Data()["tariff"].(map[string]any)
		if !ok {
			return fmt.Errorf("%s: tariff missing or not a map", snap.Ref.ID)
		}
		for _, k := range []string{"pricePerKWhSatang", "sessionFeeSatang"} {
			v := tariff[k]
			switch v.(type) {
			case int64, int:
				// good
			case float64:
				return fmt.Errorf("%s: tariff.%s is float64 — money invariant violated", snap.Ref.ID, k)
			default:
				return fmt.Errorf("%s: tariff.%s missing or wrong type (%T)", snap.Ref.ID, k, v)
			}
		}
	}
}

func (r *runner) stationsGeohashIntegrity() error {
	iter := r.fs.Collection("stations").Documents(r.ctx)
	defer iter.Stop()
	for {
		snap, err := iter.Next()
		if err == iterator.Done {
			return nil
		}
		if err != nil {
			return err
		}
		gh, _ := snap.Data()["geohash"].(string)
		if len(gh) != 9 {
			return fmt.Errorf("%s: geohash %q is %d chars, want 9", snap.Ref.ID, gh, len(gh))
		}
		// Thailand region geohash starts with 'w' (south-east Asia
		// quadrant in the geohash base32 grid).
		if !strings.HasPrefix(gh, "w") {
			return fmt.Errorf("%s: geohash %q doesn't start with 'w' (Thailand region)", snap.Ref.ID, gh)
		}
	}
}

// userACanReadStations exercises the rule
//
//	match /stations/{stationId} {
//	  allow read: if isSignedIn();
//	}
//
// by issuing the read with user A's ID token through the Firestore
// REST API. The Go SDK uses ADC and would bypass rules — REST forces
// the rule engine to evaluate the request.
func (r *runner) userACanReadStations() error {
	resp, err := r.firestoreREST(r.userA.idToken, "stations?pageSize=1")
	if err != nil {
		return err
	}
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		_ = resp.Body.Close()
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(body))
	}
	_ = resp.Body.Close()
	return nil
}

func (r *runner) anonymousCannotReadStations() error {
	resp, err := r.firestoreREST("", "stations?pageSize=1")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusUnauthorized, http.StatusForbidden:
		return nil
	default:
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("anonymous request returned HTTP %d (want 401/403): %s",
			resp.StatusCode, string(body))
	}
}

// userACanWriteOwnDoc exercises
//
//	match /users/{uid} {
//	  allow read, write: if isOwner(uid);  // request.auth.uid == uid
//	}
//
// by writing /users/{uidA} as user A.
func (r *runner) userACanWriteOwnDoc() error {
	body := map[string]any{
		"fields": map[string]any{
			"role": map[string]any{"stringValue": "consumer"},
		},
	}
	resp, err := r.firestorePATCH(r.userA.idToken,
		fmt.Sprintf("users/%s?updateMask.fieldPaths=role", r.userA.uid),
		body)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(raw))
	}
	return nil
}

func (r *runner) userACannotWriteOthersDoc() error {
	body := map[string]any{
		"fields": map[string]any{
			"role": map[string]any{"stringValue": "partner"},
		},
	}
	resp, err := r.firestorePATCH(r.userA.idToken,
		fmt.Sprintf("users/%s?updateMask.fieldPaths=role", r.userB.uid),
		body)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusForbidden, http.StatusUnauthorized:
		return nil
	default:
		raw, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("write to other user returned HTTP %d (want 403): %s",
			resp.StatusCode, string(raw))
	}
}

// ─── Cleanup ─────────────────────────────────────────────────────────

func (r *runner) cleanup(ctx context.Context) error {
	if r.authAdmin == nil {
		return nil
	}
	for _, u := range []*testUser{&r.userA, &r.userB} {
		if u.uid == "" {
			continue
		}
		if err := r.authAdmin.DeleteUser(ctx, u.uid); err != nil {
			// ignore "not found" — earlier failure may have prevented
			// signup
			continue
		}
		if r.fs != nil {
			_, _ = r.fs.Collection("users").Doc(u.uid).Delete(ctx)
		}
	}
	return nil
}

// ─── Firestore REST helpers ──────────────────────────────────────────

func (r *runner) firestoreREST(idToken, relPath string) (*http.Response, error) {
	url := fmt.Sprintf(
		"https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s",
		*flagProjectID, relPath,
	)
	req, err := http.NewRequestWithContext(r.ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	if idToken != "" {
		req.Header.Set("Authorization", "Bearer "+idToken)
	}
	return http.DefaultClient.Do(req)
}

func (r *runner) firestorePATCH(idToken, relPath string, body any) (*http.Response, error) {
	encoded, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	url := fmt.Sprintf(
		"https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s",
		*flagProjectID, relPath,
	)
	req, err := http.NewRequestWithContext(r.ctx, http.MethodPatch, url, bytes.NewReader(encoded))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if idToken != "" {
		req.Header.Set("Authorization", "Bearer "+idToken)
	}
	return http.DefaultClient.Do(req)
}

// ─── small utilities ─────────────────────────────────────────────────

func header(s string) {
	fmt.Printf("%s%s%s%s\n", cBold, cCyan, s, cReset)
	fmt.Println(strings.Repeat("─", len(s)))
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func exit(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(2)
}
