package auth

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	firebaseauth "firebase.google.com/go/v4/auth"
)

type fakeVerifier struct {
	tok *firebaseauth.Token
	err error
}

func (f *fakeVerifier) VerifyIDToken(_ context.Context, _ string) (*firebaseauth.Token, error) {
	return f.tok, f.err
}

// pass is a tiny inner handler that the middleware calls when auth
// succeeds. Each test that just checks the rejection path uses this
// to avoid repeating the boilerplate.
var pass = http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
})

func TestMiddleware_AcceptsValidToken(t *testing.T) {
	v := &fakeVerifier{tok: &firebaseauth.Token{
		UID:    "abc123",
		Claims: map[string]any{"email": "test@voltspot.dev"},
	}}
	var got User
	handler := Middleware(v)(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		u, ok := FromContext(r.Context())
		if !ok {
			t.Error("FromContext returned ok=false")
		}
		got = u
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer token-stub")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", rec.Code)
	}
	if got.UID != "abc123" || got.Email != "test@voltspot.dev" {
		t.Errorf("user = %+v, want UID=abc123 Email=test@voltspot.dev", got)
	}
}

func TestMiddleware_RejectsMissingHeader(t *testing.T) {
	handler := Middleware(&fakeVerifier{})(pass)
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401", rec.Code)
	}
}

func TestMiddleware_RejectsBadPrefix(t *testing.T) {
	handler := Middleware(&fakeVerifier{})(pass)
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Basic dXNlcjpwYXNz")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401", rec.Code)
	}
}

func TestMiddleware_RejectsVerifierError(t *testing.T) {
	v := &fakeVerifier{err: errors.New("expired")}
	handler := Middleware(v)(pass)
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer expired-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401", rec.Code)
	}
}

func TestExtractBearer(t *testing.T) {
	cases := []struct {
		header  string
		want    string
		wantErr bool
	}{
		{"", "", true},
		{"Bearer ", "", true},
		{"Bearer xyz", "xyz", false},
		{"bearer xyz", "", true}, // case-sensitive per RFC 6750 + our policy
		{"Bearer   xyz", "xyz", false},
		{"Token xyz", "", true},
	}
	for _, tc := range cases {
		got, err := extractBearer(tc.header)
		if tc.wantErr {
			if err == nil {
				t.Errorf("extractBearer(%q): expected error, got nil", tc.header)
			}
			continue
		}
		if err != nil {
			t.Errorf("extractBearer(%q): unexpected error %v", tc.header, err)
		}
		if got != tc.want {
			t.Errorf("extractBearer(%q) = %q, want %q", tc.header, got, tc.want)
		}
	}
}
