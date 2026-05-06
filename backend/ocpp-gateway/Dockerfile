# Multi-stage build: produce a tiny static binary, then ship it on
# distroless. Image runs as non-root via the static-debian:nonroot
# base — Cloud Run requires the container to listen on $PORT (default
# 8080) and to handle SIGTERM gracefully, both of which main.go does.

# ─── Builder ──────────────────────────────────────────────────────────
FROM golang:1.25-alpine AS builder

# git + ca-certificates needed by go modules over HTTPS during build.
RUN apk add --no-cache git ca-certificates

WORKDIR /src

# Pull module deps first to make rebuilds cache-friendly.
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the source tree.
COPY . .

# CGO_ENABLED=0 keeps the binary fully static so we can use distroless
# static-debian (smaller, no glibc).
# -trimpath strips local filesystem paths from stack traces — keeps
# logs from leaking the builder's directory layout.
# -ldflags "-s -w" drops the symbol table + debug info to halve the
# binary size; we still get readable Go panics because Go's runtime
# panic stacks don't depend on these sections.
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/gateway \
    ./cmd/gateway

# ─── Runtime ──────────────────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot

# Distroless has no shell; the binary is the entrypoint.
COPY --from=builder /out/gateway /gateway

# Cloud Run injects PORT; default to 8080 for local docker run.
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/gateway"]
