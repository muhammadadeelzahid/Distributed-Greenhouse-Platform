package db

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"

	_ "github.com/lib/pq"
	"sensor-net-cloud/gen/sensornetpb"
)

type DB struct {
	pool *sql.DB
}

func New(connString string) (*DB, error) {
	db, err := sql.Open("postgres", connString)
	if err != nil {
		return nil, err
	}
	if err := db.Ping(); err != nil {
		return nil, err
	}
	return &DB{pool: db}, nil
}

func (db *DB) Close() error {
	return db.pool.Close()
}

func (db *DB) RegisterGateway(ctx context.Context, gatewayID, softwareVersion string) (string, error) {
	query := `
		INSERT INTO gateways (gateway_id, software_version, status)
		VALUES ($1, $2, 'online')
		ON CONFLICT (gateway_id) DO UPDATE 
		SET software_version = EXCLUDED.software_version, 
		    last_seen = now(), 
		    status = 'online'
	`
	_, err := db.pool.ExecContext(ctx, query, gatewayID, softwareVersion)
	if err != nil {
		return "", err
	}
	return "v1", nil
}

func (db *DB) UploadTelemetry(ctx context.Context, gatewayID string, records []*sensornetpb.TelemetryRecord) ([]int64, error) {
	var accepted []int64

	// Update last_seen
	_, _ = db.pool.ExecContext(ctx, `UPDATE gateways SET last_seen = now() WHERE gateway_id = $1`, gatewayID)

	query := `
		INSERT INTO telemetry (gateway_id, device_id, local_id, timestamp_ms, payload)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (gateway_id, local_id) DO NOTHING
	`
	for _, rec := range records {
		_, err := db.pool.ExecContext(ctx, query, gatewayID, rec.DeviceId, rec.LocalId, rec.TimestampMs, rec.PayloadJson)
		if err != nil {
			log.Printf("Error inserting telemetry (local_id: %d): %v", rec.LocalId, err)
			continue
		}
		// In ON CONFLICT DO NOTHING, if it was skipped it's already there, so we still accept it.
		accepted = append(accepted, rec.LocalId)
	}
	return accepted, nil
}

func (db *DB) CheckCommands(ctx context.Context, gatewayID string) ([]*sensornetpb.CloudCommand, error) {
	// Update last_seen
	_, _ = db.pool.ExecContext(ctx, `UPDATE gateways SET last_seen = now() WHERE gateway_id = $1`, gatewayID)

	query := `
		SELECT command_id, target_device_id, payload 
		FROM commands 
		WHERE gateway_id = $1 AND status = 'pending' 
		ORDER BY created_at ASC 
		LIMIT 20
	`
	rows, err := db.pool.QueryContext(ctx, query, gatewayID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var commands []*sensornetpb.CloudCommand
	var commandIDs []string

	for rows.Next() {
		var cmd sensornetpb.CloudCommand
		var payloadJSON json.RawMessage
		if err := rows.Scan(&cmd.CommandId, &cmd.TargetDeviceId, &payloadJSON); err != nil {
			return nil, err
		}
		cmd.PayloadJson = string(payloadJSON)
		commands = append(commands, &cmd)
		commandIDs = append(commandIDs, cmd.CommandId)
	}

	if len(commandIDs) > 0 {
		// Convert slice of strings to array string for postgres
		// This requires pq.Array, but let's do a simple loop or use pq.Array if pq is imported
		// Wait, pq is imported as _, so we can't use pq.Array directly unless we import it normally.
		// Let's use a simpler query execution per ID or just import pq.
		// I will rewrite this to use a simple loop to avoid pq dependency for Array since I imported it as _
		for _, id := range commandIDs {
			_, _ = db.pool.ExecContext(ctx, `UPDATE commands SET status = 'delivered', delivered_at = now() WHERE command_id = $1`, id)
		}
	}

	return commands, nil
}

func (db *DB) ReportCommandResult(ctx context.Context, gatewayID, commandID, status, resultJSON string) error {
	// Update last_seen
	_, _ = db.pool.ExecContext(ctx, `UPDATE gateways SET last_seen = now() WHERE gateway_id = $1`, gatewayID)

	query := `
		UPDATE commands 
		SET status = $1, completed_at = now(), result = $2
		WHERE command_id = $3 AND gateway_id = $4
	`
	_, err := db.pool.ExecContext(ctx, query, status, resultJSON, commandID, gatewayID)
	return err
}

func (db *DB) ReportHealth(ctx context.Context, gatewayID, payloadJSON string) error {
	// Update last_seen
	_, _ = db.pool.ExecContext(ctx, `UPDATE gateways SET last_seen = now() WHERE gateway_id = $1`, gatewayID)

	query := `INSERT INTO health_reports (gateway_id, payload) VALUES ($1, $2)`
	_, err := db.pool.ExecContext(ctx, query, gatewayID, payloadJSON)
	return err
}

func (db *DB) ReportOtaStatus(ctx context.Context, gatewayID, updateID, targetVersion, status, detail string) error {
	// Update last_seen
	_, _ = db.pool.ExecContext(ctx, `UPDATE gateways SET last_seen = now() WHERE gateway_id = $1`, gatewayID)

	query := `
		INSERT INTO ota_results (gateway_id, update_id, target_version, status, detail) 
		VALUES ($1, $2, $3, $4, $5)
	`
	_, err := db.pool.ExecContext(ctx, query, gatewayID, updateID, targetVersion, status, detail)
	return err
}
