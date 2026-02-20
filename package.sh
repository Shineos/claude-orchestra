#!/bin/bash
set -e

# Create a temporary directory for packaging
mkdir -p dist/claude-orchestra/bin

# Build binaries
echo "Building control-center for macOS (Apple Silicon)..."
GOOS=darwin GOARCH=arm64 go build -o dist/claude-orchestra/bin/control-center-darwin-arm64 cmd/control-center/main.go

echo "Building control-center for macOS (Intel)..."
GOOS=darwin GOARCH=amd64 go build -o dist/claude-orchestra/bin/control-center-darwin-amd64 cmd/control-center/main.go

echo "Building control-center for Linux (x64)..."
GOOS=linux GOARCH=amd64 go build -o dist/claude-orchestra/bin/control-center-linux-amd64 cmd/control-center/main.go

# Copy other files
echo "Copying scripts..."
cp install.sh dist/claude-orchestra/
cp -r .claude dist/claude-orchestra/

# Create tarball
echo "Creating archive..."
cd dist
tar -czf claude-orchestra.tar.gz claude-orchestra

echo "Done: dist/claude-orchestra.tar.gz"
echo "Upload this file to your GitHub Release."
