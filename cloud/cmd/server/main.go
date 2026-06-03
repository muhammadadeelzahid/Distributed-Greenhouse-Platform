package main

import (
	"log"
	"net/http"
	"os"
	"strings"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"sensor-net-cloud/gen/sensornetpb"
	"sensor-net-cloud/internal/db"
	"sensor-net-cloud/internal/grpcserver"
	"sensor-net-cloud/internal/migrations"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL environment variable is required")
	}

	// Run migrations
	if err := migrations.Run(dbURL); err != nil {
		log.Fatalf("Migration failed: %v", err)
	}

	// Connect to database
	database, err := db.New(dbURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer database.Close()

	// Initialize gRPC server
	grpcSrv := grpc.NewServer()
	sensornetpb.RegisterGatewayCloudServiceServer(grpcSrv, grpcserver.New(database))

	// Enable reflection for development/testing
	reflection.Register(grpcSrv)

	// Set up HTTP health endpoint
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	})

	// Multiplex gRPC and HTTP
	mixedHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("Received request: %s %s Proto=%d.%d Content-Type=%s", r.Method, r.URL.Path, r.ProtoMajor, r.ProtoMinor, r.Header.Get("Content-Type"))
		
		if r.ProtoMajor == 2 && strings.HasPrefix(r.Header.Get("Content-Type"), "application/grpc") {
			grpcSrv.ServeHTTP(w, r)
		} else {
			mux.ServeHTTP(w, r)
		}
	})

	// Use h2c to handle HTTP/1.1 Upgrade requests from Render proxy
	h2cHandler := h2c.NewHandler(mixedHandler, &http2.Server{})

	httpSrv := &http.Server{
		Addr:    "0.0.0.0:" + port,
		Handler: h2cHandler,
	}

	log.Printf("Starting mixed h2c server on port %s...", port)
	if err := httpSrv.ListenAndServe(); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}
