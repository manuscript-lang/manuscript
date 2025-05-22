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
		-debug \
		-file $(f))

update-file:
	@echo "Updating single file test: $(f)"
	@(go test -v ./cmd/... -run ^TestCompile$$ -timeout 30s -args -update -file $(f))

profile-test:
	cd cmd && go test -c -o main.test
	cd cmd && ./main.test -test.v -test.run ^TestCompile$$ -test.cpuprofile=cpu.prof
	cd cmd && go tool pprof -http=:8080 ./main.test cpu.prof

DIR = tests/minimal
minimal-generate-parser:
	cd $(DIR)/grammar && java -jar "../../../build/antlr-4.13.1-complete.jar" -Dlanguage=Go -o ../parser -visitor -listener ToyLexer.g4 Toy.g4
	echo "Done!" 

minimal-run:
	cd $(DIR) && go run main/main.go
