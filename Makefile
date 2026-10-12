GO ?= go
export MANUSCRIPT_GO ?= $(GO)

.PHONY: build test e2e race check fmt

build:
	$(GO) build -o ms ./cmd/ms

test:
	$(GO) test ./...

e2e:
	$(GO) test ./tests/e2e

race:
	$(GO) test -race ./runtime ./checker ./compiler ./tooling

check:
	@test -z "$$($(GO) fmt ./...)" || (echo 'Go files need formatting'; exit 1)
	$(GO) vet ./...

fmt:
	$(GO) fmt ./...

.PHONY: docs docs-check
docs:
	$(GO) run ./cmd/docgen

docs-check:
	$(GO) run ./cmd/docgen -check
