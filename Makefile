clean_install: clean install

install: 
	go build -ldflags '-s -w' -o build/msc cmd/main.go 

clean: 
	rm -rf build/

test:
	go test ./...

generate_parser:
	@echo "Generating parser from grammar..."
	@./scripts/generate_parser.sh
	@go mod tidy

build: generate_parser install

.PHONY: test-file
test-file:
	@echo "Running single file test: $(f)"
	go test -v ./cmd/... -run ^TestMarkdownCompilation$$ -timeout 30s -args -file $(f) $(if findstring args debug, -debug)