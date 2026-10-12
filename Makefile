GO ?= $(CURDIR)/toolchain/go/bin/go
HUGO ?= hugo
FUZZTIME ?= 10s
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation
export MANUSCRIPT_GO ?= $(GO)
export PATH := $(dir $(GO)):$(PATH)

.PHONY: build test e2e race check fmt toolchain payload dist dist-check coverage fuzz book book-check

toolchain:
	sh scripts/bootstrap-go.sh

build test e2e race check fmt docs docs-check coverage fuzz: | toolchain

payload: | toolchain
	CGO_ENABLED=0 "$(GO)" run ./scripts/mktoolchain "$(CURDIR)/toolchain/go" .build-payload.tar.gz $$("$(GO)" env GOHOSTOS) $$("$(GO)" env GOHOSTARCH)

build: payload
	CGO_ENABLED=0 "$(GO)" build -trimpath -mod=vendor -tags bundled_toolchain -o ms ./cmd/ms

test:
	"$(GO)" test ./...

e2e:
	"$(GO)" test ./tests/e2e

race:
	"$(GO)" test -race ./runtime ./checker ./compiler ./project ./internal/cli ./tooling/...

coverage:
	@mkdir -p .artifacts/coverage
	"$(GO)" test -covermode=atomic -coverprofile=.artifacts/coverage/coverage.out ./...
	"$(GO)" tool cover -func=.artifacts/coverage/coverage.out
	"$(GO)" tool cover -html=.artifacts/coverage/coverage.out -o .artifacts/coverage/index.html

fuzz:
	"$(GO)" test ./parser -run '^$$' -fuzz '^FuzzParse$$' -fuzztime "$(FUZZTIME)"
	"$(GO)" test ./parser -run '^$$' -fuzz '^FuzzParsePartial$$' -fuzztime "$(FUZZTIME)"
	"$(GO)" test ./compiler -run '^$$' -fuzz '^FuzzCompile$$' -fuzztime "$(FUZZTIME)"

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
	"$(GO)" run ./scripts/docgen

docs-check:
	"$(GO)" run ./scripts/docgen -check

book: docs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir

book-check: docs-check
	node --test tests/docs/highlighting.test.cjs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir --destination "$(BOOK_CHECK_DIR)" --baseURL "https://example.org/manuscript/"
	MANUSCRIPT_BOOK_DIR="$(BOOK_CHECK_DIR)" node --test tests/docs/publication.test.cjs
