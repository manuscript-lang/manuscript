clean_install: clean install

install: 
	go build -ldflags '-s -w' -o build/msc cmd/main.go 

clean: 
	rm -rf build/

test:
	go test ./...

test-cov:
	go test ./... -coverprofile=./cover.out -covermode=atomic -coverpkg=./...
	go tool cover -html=./cover.out -o cover.html

generate_parser:
	@echo "Generating parser from grammar..."
	@./scripts/generate_parser.sh
	@go mod tidy

build: generate_parser install

.PHONY: test-file
test-file:
	@echo "Running single file test: $(f)"
	@(go test -v ./cmd/... \
		-run ^TestCompile$$ \
		-timeout 30s \
		-args \
		$(if $(findstring debug,$(args)),-debug) \
		$(if $(findstring update,$(args)),-update) \
		-file $(f))