GO ?= $(CURDIR)/toolchain/go/bin/go
HUGO ?= hugo
FUZZTIME ?= 10s
BENCHREPEATS ?= 5
BENCHFILTER ?=
E2EFLAGS ?=
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation
export PATH := $(dir $(GO)):$(PATH)
export STATICCHECK_CACHE ?= $(CURDIR)/.artifacts/staticcheck

.PHONY: stdgen agent-bench-check toolchain setup tools doctor verify verify-full lint unit stdlib-check stdlib-test stdlib-bench repo-check examples-check licenses licenses-check payload build test e2e race coverage fuzz check fmt dist dist-check docs docs-check docs-coverage book book-check vendor-refresh

toolchain:
	sh scripts/bootstrap-go.sh

check lint repo-check unit stdlib-check stdlib-test examples-check licenses licenses-check test e2e race coverage fuzz fmt docs docs-check docs-coverage: | payload

setup: payload tools

tools: | toolchain
	sh scripts/bootstrap-tools.sh

doctor:
	HUGO="$(HUGO)" sh scripts/doctor.sh

# Routine feedback excludes native compilation. The merge gate adds native checks.
verify: check lint repo-check unit stdlib-check docs-check examples-check licenses-check

verify-full: verify coverage race fuzz book-check dist-check

check:
	"$(GO)" run ./scripts/repo-check -format
	"$(GO)" vet ./...

lint:
	@test -x .tools/staticcheck -a -x .tools/actionlint -a -x .tools/shellcheck || (echo 'Run make setup to install pinned linters'; exit 1)
	.tools/staticcheck ./...
	.tools/actionlint -shellcheck .tools/shellcheck
	.tools/shellcheck -x scripts/*.sh

repo-check:
	"$(GO)" run ./scripts/repo-check

unit:
	"$(GO)" test ./pkg/syntax ./pkg/lexer ./pkg/parser ./pkg/frontend ./pkg/project ./pkg/stdlib ./pkg/checker ./pkg/runtime ./pkg/tooling/... ./scripts/repo-check

stdlib-check:
	"$(GO)" test ./tests/e2e -run '^TestStandardLibrarySources$$'

stdlib-test:
	"$(GO)" test $(E2EFLAGS) ./tests/e2e -run '^TestStandardLibrary(Sources|Conformance|Faults)$$'

examples-check:
	"$(GO)" test ./tests/examples

licenses:
	"$(GO)" run ./scripts/maintenance licenses

licenses-check:
	"$(GO)" run ./scripts/maintenance licenses -check

stdgen: | toolchain
	"$(GO)" run ./scripts/stdgen pkg/runtime

payload: .build-payload.tar.gz

# Rebuilt only when the pinned SDK, packaging code, or runtime imports change.
.build-payload.tar.gz: .go-version go.mod $(wildcard scripts/mktoolchain/*.go scripts/internal/devtool/*.go pkg/runtime/*.go) | toolchain
	CGO_ENABLED=0 "$(GO)" run ./scripts/mktoolchain "$(CURDIR)/toolchain/go" .build-payload.tar.gz $$("$(GO)" env GOHOSTOS) $$("$(GO)" env GOHOSTARCH)

build: payload
	CGO_ENABLED=0 "$(GO)" build -trimpath -mod=vendor -tags exp.winarm64 -o ms ./cmd/ms

test:
	"$(GO)" test ./...

agent-bench-check: build
	PATH="$(CURDIR):$$PATH" python3 agent-bench/run.py oracle
	python3 -m unittest discover -s agent-bench/tests

stdlib-bench: build
	scripts/stdlib-bench.sh $(BENCHREPEATS) $(BENCHFILTER)

e2e:
	"$(GO)" test $(E2EFLAGS) ./tests/e2e

race:
	"$(GO)" test -race $$(cat scripts/race-packages)

coverage:
	@mkdir -p .artifacts/coverage
	MANUSCRIPT_EXAMPLES_NATIVE=1 "$(GO)" test -covermode=atomic -coverpkg="$$("$(GO)" list ./... | paste -sd, -)" -coverprofile=.artifacts/coverage/coverage.out ./...
	"$(GO)" tool cover -func=.artifacts/coverage/coverage.out
	"$(GO)" tool cover -html=.artifacts/coverage/coverage.out -o .artifacts/coverage/index.html

fuzz:
	"$(GO)" test ./pkg/parser -run '^$$' -fuzz '^FuzzParse$$' -fuzztime "$(FUZZTIME)"
	"$(GO)" test ./pkg/parser -run '^$$' -fuzz '^FuzzParsePartial$$' -fuzztime "$(FUZZTIME)"
	"$(GO)" test ./pkg/tooling -run '^$$' -fuzz '^FuzzFormat$$' -fuzztime "$(FUZZTIME)"
	"$(GO)" test ./pkg/runtime -run '^$$' -fuzz '^FuzzJSONRoundTrip$$' -fuzztime "$(FUZZTIME)"
	"$(GO)" test ./pkg/runtime -run '^$$' -fuzz '^FuzzCSVRoundTrip$$' -fuzztime "$(FUZZTIME)"
	"$(GO)" test ./pkg/runtime -run '^$$' -fuzz '^FuzzCodecRoundTrip$$' -fuzztime "$(FUZZTIME)"
	"$(GO)" test ./pkg/runtime -run '^$$' -fuzz '^FuzzURLFormatStable$$' -fuzztime "$(FUZZTIME)"
	@targets=$$("$(GO)" test ./pkg/build -list '^FuzzCompile$$') && \
		printf '%s\n' "$$targets" | grep -qxF FuzzCompile || \
		{ echo 'FuzzCompile is not discoverable in pkg/build' >&2; exit 1; }
	"$(GO)" test ./pkg/build -run '^$$' -fuzz '^FuzzCompile$$' -fuzztime "$(FUZZTIME)"

fmt:
	"$(GO)" fmt ./...

dist: | toolchain
	sh scripts/package.sh

dist-check: dist
	"$(GO)" run ./scripts/distcheck ./dist/manuscript-$$("$(GO)" env GOHOSTOS)-$$("$(GO)" env GOHOSTARCH)

docs:
	"$(GO)" run ./scripts/docgen

docs-check:
	"$(GO)" run ./scripts/docgen -check

docs-coverage:
	"$(GO)" run ./scripts/docgen -check -coverage .artifacts/stdlib-doc-coverage.json

book: docs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir

book-check: docs-check docs
	node --test tests/docs/highlighting.test.cjs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir --destination "$(BOOK_CHECK_DIR)" --baseURL "https://example.org/manuscript/"
	MANUSCRIPT_BOOK_DIR="$(BOOK_CHECK_DIR)" node --test tests/docs/publication.test.cjs

vendor-refresh:
	"$(GO)" run ./scripts/maintenance vendor
