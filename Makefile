GO ?= $(CURDIR)/toolchain/go/bin/go
export MANUSCRIPT_GO ?= $(GO)

.PHONY: build test e2e race check fmt toolchain payload dist dist-check

toolchain:
	sh scripts/bootstrap-go.sh

build test e2e race check fmt docs docs-check: | toolchain

payload: | toolchain
	CGO_ENABLED=0 "$(GO)" run ./scripts/mktoolchain "$(CURDIR)/toolchain/go" .build-payload.tar.gz $$("$(GO)" env GOHOSTOS) $$("$(GO)" env GOHOSTARCH)

build: payload
	CGO_ENABLED=0 "$(GO)" build -trimpath -mod=vendor -tags bundled_toolchain -o ms ./cmd/ms

test:
	"$(GO)" test ./...

e2e:
	"$(GO)" test ./tests/e2e

race:
	"$(GO)" test -race ./runtime ./checker ./compiler ./tooling/...

check:
	@test -z "$$("$(GO)" fmt ./...)" || (echo 'Go files need formatting'; exit 1)
	"$(GO)" vet ./...

fmt:
	"$(GO)" fmt ./...

dist: | toolchain
	sh scripts/package.sh

dist-check: dist
	"$(GO)" run ./scripts/distcheck ./dist/manuscript-$$("$(GO)" env GOHOSTOS)-$$("$(GO)" env GOHOSTARCH)

.PHONY: docs docs-check
docs:
	"$(GO)" run ./cmd/docgen

docs-check:
	"$(GO)" run ./cmd/docgen -check
