package grpcserver

import (
	"context"
	"log"

	"sensor-net-cloud/gen/sensornetpb"
	"sensor-net-cloud/internal/db"
)

type Server struct {
	sensornetpb.UnimplementedGatewayCloudServiceServer
	db *db.DB
}

func New(database *db.DB) *Server {
	return &Server{db: database}
}

func (s *Server) RegisterGateway(ctx context.Context, req *sensornetpb.RegisterGatewayRequest) (*sensornetpb.RegisterGatewayResponse, error) {
	configVer, err := s.db.RegisterGateway(ctx, req.GatewayId, req.SoftwareVersion)
	if err != nil {
		log.Printf("Error registering gateway: %v", err)
		return nil, err
	}
	return &sensornetpb.RegisterGatewayResponse{
		Accepted:      true,
		ConfigVersion: configVer,
	}, nil
}

func (s *Server) UploadTelemetry(ctx context.Context, req *sensornetpb.UploadTelemetryRequest) (*sensornetpb.UploadTelemetryResponse, error) {
	accepted, err := s.db.UploadTelemetry(ctx, req.GatewayId, req.Records)
	if err != nil {
		log.Printf("Error uploading telemetry: %v", err)
		return nil, err
	}
	return &sensornetpb.UploadTelemetryResponse{
		AcceptedLocalIds: accepted,
	}, nil
}

func (s *Server) CheckCommands(ctx context.Context, req *sensornetpb.CheckCommandsRequest) (*sensornetpb.CheckCommandsResponse, error) {
	cmds, err := s.db.CheckCommands(ctx, req.GatewayId)
	if err != nil {
		log.Printf("Error checking commands: %v", err)
		return nil, err
	}
	return &sensornetpb.CheckCommandsResponse{
		Commands:          cmds,
		NextCommandCursor: "", // Not implemented in MVP
	}, nil
}

func (s *Server) ReportCommandResult(ctx context.Context, req *sensornetpb.ReportCommandResultRequest) (*sensornetpb.ReportCommandResultResponse, error) {
	err := s.db.ReportCommandResult(ctx, req.GatewayId, req.CommandId, req.Status, req.ResultJson)
	if err != nil {
		log.Printf("Error reporting command result: %v", err)
		return nil, err
	}
	return &sensornetpb.ReportCommandResultResponse{
		Accepted: true,
	}, nil
}

func (s *Server) ReportHealth(ctx context.Context, req *sensornetpb.ReportHealthRequest) (*sensornetpb.ReportHealthResponse, error) {
	err := s.db.ReportHealth(ctx, req.GatewayId, req.PayloadJson)
	if err != nil {
		log.Printf("Error reporting health: %v", err)
		return nil, err
	}
	return &sensornetpb.ReportHealthResponse{
		Accepted: true,
	}, nil
}

func (s *Server) ReportOtaStatus(ctx context.Context, req *sensornetpb.ReportOtaStatusRequest) (*sensornetpb.ReportOtaStatusResponse, error) {
	err := s.db.ReportOtaStatus(ctx, req.GatewayId, req.UpdateId, req.TargetVersion, req.Status, req.Detail)
	if err != nil {
		log.Printf("Error reporting OTA status: %v", err)
		return nil, err
	}
	return &sensornetpb.ReportOtaStatusResponse{
		Accepted: true,
	}, nil
}
