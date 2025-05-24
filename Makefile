clean_install: clean build-msc

build-msc: 
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

build: generate_parser build-msc

.PHONY: test-file
test-file:
	@echo "Running single file test: $(f)"
	@(go test -v ./cmd/... \
		-run ^TestCompile$$ \
		-timeout 30s \
		-args \
		-debug \
		-file $(f))

update-file:
	@echo "Updating single file test: $(f)"
	@(go test -v ./cmd/... -run ^TestCompile$$ -timeout 30s -args -update -file $(f))

profile-test:
	cd cmd && go test -c -o main.test
	cd cmd && ./main.test -test.v -test.run ^TestCompile$$ -test.cpuprofile=cpu.prof
	cd cmd && go tool pprof -http=:8080 ./main.test cpu.prof

build-lsp:
	go build -ldflags '-s -w' -o build/msc-lsp tools/lsp/main.go

build-vscode-extension: build-lsp
	cp build/msc-lsp tools/manuscript-vscode-extension/msc-lsp
	cd tools/manuscript-vscode-extension && npm run build

# Documentation website targets
HUGO_BIN := $(shell [ -x build/hugo ] && echo ../../build/hugo || echo hugo)

download-hugo-darwin:
	@curl -L https://github.com/gohugoio/hugo/releases/download/v0.125.7/hugo_extended_0.125.7_darwin-universal.tar.gz -o build/hugo.tar.gz
	@tar -xzf build/hugo.tar.gz -C build/
	@rm build/hugo.tar.gz
	build/hugo version

build-docs:
	@echo "Updating Hugo modules..."
	@cd tools/docs-web && $(HUGO_BIN) mod tidy
	@echo "Building documentation website..."
	@cd tools/docs-web && $(HUGO_BIN) --destination ../../build/docs-web

serve-docs:
	@echo "Updating Hugo modules..."
	@cd tools/docs-web && $(HUGO_BIN) mod tidy
	@echo "Serving documentation website locally..."
	@cd tools/docs-web && $(HUGO_BIN) server --bind 0.0.0.0 --port 1313 --destination ../../build/docs-web

clean-docs:
	@echo "Cleaning documentation build..."
	@rm -rf build/docs-web

build-all: build-msc build-lsp build-vscode-extension build-docs


DIR = tests/minimal
minimal-generate-parser:
	cd $(DIR)/grammar && java -jar "../../../build/antlr-4.13.1-complete.jar" -Dlanguage=Go -o ../parser -visitor -listener ToyLexer.g4 Toy.g4
	echo "Done!" 

minimal-run:
	cd $(DIR) && go run main/main.go
