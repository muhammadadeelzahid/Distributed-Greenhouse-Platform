package migrations

import (
	"log"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

func Run(dbURL string) error {
	// The path to the migrations folder needs to be accessible where the app runs.
	// We'll assume the migrations folder is in the working directory (e.g., ./migrations)
	m, err := migrate.New("file://migrations", dbURL)
	if err != nil {
		log.Printf("Failed to initialize migrations: %v", err)
		return err
	}

	if err := m.Up(); err != nil {
		if err == migrate.ErrNoChange {
			log.Println("No database migrations to apply.")
			return nil
		}
		log.Printf("Failed to run migrations: %v", err)
		return err
	}

	log.Println("Database migrations applied successfully.")
	return nil
}
