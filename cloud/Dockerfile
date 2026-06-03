FROM golang:1.26-bookworm AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /out/sensor-net-cloud ./cmd/server

FROM debian:bookworm-slim

WORKDIR /app

COPY --from=build /out/sensor-net-cloud /app/sensor-net-cloud
COPY migrations /app/migrations

EXPOSE 8080

CMD ["/app/sensor-net-cloud"]
