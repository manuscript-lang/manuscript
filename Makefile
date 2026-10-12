GO ?= $(CURDIR)/toolchain/go/bin/go
HUGO ?= hugo
FUZZTIME ?= 10s
E2EFLAGS ?=
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation
export MANUSCRIPT_GO ?= $(GO)
export PATH := $(dir $(GO)):$(PATH)
export STATICCHECK_CACHE ?= $(CURDIR)/.artifacts/staticcheck

.PHONY: build test e2e race check fmt toolchain payload dist dist-check coverage fuzz book book-check

toolchain:
	sh scripts/bootstrap-go.sh

build test e2e race fmt coverage fuzz: | toolchain

.PHONY: setup tools doctor verify verify-full lint unit repo-check examples-check licenses licenses-check
setup: toolchain tools

tools: | toolchain
	sh scripts/bootstrap-tools.sh

doctor:
	HUGO="$(HUGO)" sh scripts/doctor.sh

# Routine feedback excludes native compilation. The merge gate runs verify-full.
verify: check lint repo-check unit docs-check examples-check licenses-check

verify-full: verify coverage race fuzz book-check dist-check

lint:
	@test -x .tools/staticcheck -a -x .tools/actionlint -a -x .tools/shellcheck || (echo 'Run make setup to install pinned linters'; exit 1)
	.tools/staticcheck ./...
	.tools/actionlint -shellcheck .tools/shellcheck
	.tools/shellcheck -x scripts/*.sh

unit:
	"$(GO)" test ./syntax ./lexer ./parser ./project ./checker ./runtime ./tooling/... ./scripts/repo-check

repo-check:
	"$(GO)" run ./scripts/repo-check -format
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

.PHONY: vendor-refresh
vendor-refresh:
	"$(GO)" run ./scripts/maintenance vendor
