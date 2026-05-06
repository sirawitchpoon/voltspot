// Package auth verifies Firebase ID tokens on inbound REST requests.
//
// Mobile clients send Authorization: Bearer <id-token> using the
// short-lived ID token from the Firebase iOS SDK. We verify locally
// against Google's public keys (cached + auto-rotated by the Admin
// SDK) so the call is fast and works offline of the auth service for
// short outages.
package auth

import (
	"context"
	"errors"
	"net/http"
	"strings"

	firebaseauth "firebase.google.com/go/v4/auth"
)

// userKey is the type used for context.WithValue lookups so it can't
// collide with another package's key. Defined as a struct{} per Go
// best practice — typed empty struct uses zero memory.
type userKey struct{}

// User is the verified principal extracted from an ID token. UID
// uniquely identifies the Firebase Auth user; Email is informational
// and may be empty for anonymous or phone-only accounts.
type User struct {
	UID   string
	Email string
}

// FromContext returns the verified user previously stored by
// Middleware. ok=false when the request hasn't been through the
// middleware (caller should treat as 500 Internal Server Error
// since handlers behind the middleware should never see this).
func FromContext(ctx context.Context) (User, bool) {
	u, ok := ctx.Value(userKey{}).(User)
	return u, ok
}

// Verifier is the subset of firebaseauth.Client we use. Decoupled so
// tests can inject a fake without standing up the real SDK.
type Verifier interface {
	VerifyIDToken(ctx context.Context, token string) (*firebaseauth.Token, error)
}

// Middleware returns an HTTP middleware that verifies the bearer
// token, attaches the resolved User to the request context, and
// rejects the request with a 401 if anything's wrong.
//
// Common rejection reasons (in priority order):
//   - missing / malformed Authorization header → 401
//   - expired token → 401 (client should refresh and retry)
//   - revoked token → 401
//   - signature mismatch → 401
//   - any other verification error → 401
//
// The body of the 401 is intentionally vague — the Authorization
// header is sensitive and we don't want to leak whether a token was
// expired vs forged to a probe.
func Middleware(v Verifier) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tok, err := extractBearer(r.Header.Get("Authorization"))
			if err != nil {
				unauthorized(w)
				return
			}

			decoded, err := v.VerifyIDToken(r.Context(), tok)
			if err != nil {
				unauthorized(w)
				return
			}

			user := User{UID: decoded.UID}
			if v, ok := decoded.Claims["email"].(string); ok {
				user.Email = v
			}

			ctx := context.WithValue(r.Context(), userKey{}, user)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// extractBearer pulls the token from a "Bearer xxx" header. Trims
// whitespace and rejects mixed-case "bearer" / missing token.
func extractBearer(header string) (string, error) {
	if header == "" {
		return "", errors.New("auth: missing Authorization header")
	}
	const prefix = "Bearer "
	if !strings.HasPrefix(header, prefix) {
		return "", errors.New("auth: Authorization must start with Bearer")
	}
	tok := strings.TrimSpace(header[len(prefix):])
	if tok == "" {
		return "", errors.New("auth: empty bearer token")
	}
	return tok, nil
}

// unauthorized writes a minimal 401 response. Body is plain text so
// the iOS GatewayAPIClient can show a generic "Sign in expired"
// message without trying to parse JSON it might not get.
func unauthorized(w http.ResponseWriter) {
	w.Header().Set("WWW-Authenticate", `Bearer realm="voltspot"`)
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusUnauthorized)
	_, _ = w.Write([]byte("unauthorized\n"))
}
