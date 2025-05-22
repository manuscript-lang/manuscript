# Makefile for Manuscript LSP Server

BINARY_NAME=manuscript-lsp
OUTPUT_DIR=./bin
MAIN_GO_PATH=./cmd/manuscript-lsp/main.go

# Default target
all: build

# Build the Go executable
build:
	@echo "Building Manuscript LSP server..."
	@mkdir -p $(OUTPUT_DIR)
	go build -o $(OUTPUT_DIR)/$(BINARY_NAME) $(MAIN_GO_PATH)
	@echo "Build complete: $(OUTPUT_DIR)/$(BINARY_NAME)"

# Clean the build output
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(OUTPUT_DIR)
	@echo "Clean complete."

# Run the LSP server (for local testing, though LSP usually started by client)
run: build
	@echo "Running Manuscript LSP server (manual test)..."
	$(OUTPUT_DIR)/$(BINARY_NAME)

.PHONY: all build clean run
