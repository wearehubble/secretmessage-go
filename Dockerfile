# Self-hosted Secret Message. The build runs the test suite, so a failing test stops the image.
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
COPY pkg ./pkg
# The tests use SQLite, which needs cgo; the shipped binary is built without it.
RUN apk add --no-cache build-base && CGO_ENABLED=1 go test ./pkg/...
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/secretmessage .

FROM alpine:3.22
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 app
COPY --from=build /out/secretmessage /usr/local/bin/secretmessage
USER app
ENV PORT=8080
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/health >/dev/null || exit 1
CMD ["secretmessage"]
