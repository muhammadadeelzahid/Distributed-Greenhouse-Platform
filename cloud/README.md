# Sensor Net Cloud

This is the cloud/server side for an embedded greenhouse/garden distributed system. It provides a gRPC API for Raspberry Pi gateways to register, upload telemetry, and receive commands.

## Setup Locally

1. **Initialize Module**
   \`\`\`bash
   go mod init sensor-net-cloud
   \`\`\`

2. **Generate gRPC Code**
   Make sure you have `protoc`, `protoc-gen-go`, and `protoc-gen-go-grpc` installed.
   \`\`\`bash
   protoc --go_out=. --go-grpc_out=. proto/sensornet.proto
   \`\`\`

3. **Install Dependencies**
   \`\`\`bash
   go mod tidy
   \`\`\`

4. **Run PostgreSQL Locally**
   \`\`\`bash
   export DATABASE_URL="postgres://user:password@localhost:5432/sensor-net?sslmode=disable"
   \`\`\`

5. **Run the Server**
   \`\`\`bash
   export PORT=8080
   go run ./cmd/server
   \`\`\`

## Testing with grpcurl

List available services:
\`\`\`bash
grpcurl localhost:8080 list
\`\`\`

Test Gateway Registration:
\`\`\`bash
grpcurl -plaintext -d '{"gateway_id":"gateway-001","software_version":"0.1.0"}' localhost:8080 sensornet.GatewayCloudService/RegisterGateway
\`\`\`

## Deployment

Deploy this to Render using the provided `render.yaml` file. The server requires the `DATABASE_URL` and `PORT` environment variables which Render handles automatically.
