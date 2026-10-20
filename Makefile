GO ?= $(CURDIR)/toolchain/go/bin/go
HUGO ?= hugo
FUZZTIME ?= 10s
BENCHREPEATS ?= 5
BENCHFILTER ?=
CONFORMANCE_SUITE ?= all
CONFORMANCE_SHARD ?= 0
CONFORMANCE_SHARDS ?= 1
E2EFLAGS ?=
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation
export PATH := $(dir $(GO)):$(PATH)
export STATICCHECK_CACHE ?= $(CURDIR)/.artifacts/staticcheck

.PHONY: conformance conform-oracle conform-rust stdgen agent-bench-check toolchain setup tools doctor verify verify-full lint unit stdlib-check stdlib-test stdlib-bench repo-check repo-check-go examples-check licenses licenses-check payload build test e2e race coverage fuzz check fmt dist dist-check docs docs-check docs-coverage docs-rs docs-check-rs docs-parity book book-check vendor-refresh

toolchain:
	sh scripts/bootstrap-go.sh

check lint repo-check-go unit stdlib-check stdlib-test examples-check licenses licenses-check test e2e race coverage fuzz fmt docs docs-check docs-coverage docs-parity: | payload

setup: payload tools

tools: | toolchain
	sh scripts/bootstrap-tools.sh

doctor:
	HUGO="$(HUGO)" sh scripts/doctor.sh

# Routine feedback excludes native compilation. The merge gate adds native checks.
verify: check lint repo-check repo-check-go unit stdlib-check docs-check examples-check licenses-check

verify-full: verify coverage race fuzz book-check dist-check

check:
	"$(GO)" run ./scripts/repo-check -format
	"$(GO)" vet ./...

lint:
	@test -x .tools/staticcheck -a -x .tools/actionlint -a -x .tools/shellcheck || (echo 'Run make setup to install pinned linters'; exit 1)
	.tools/staticcheck ./...
	.tools/actionlint -shellcheck .tools/shellcheck
	.tools/shellcheck -x scripts/*.sh

# Nested matches, .ms formatting, stdlib syntax, release pins, workflow triggers, Rust unsafe allow-list.
repo-check:
	cargo run --release --locked -q -p ms-repo-check

# Go-only package boundaries and native bundle pins; retires with the Go implementation.
repo-check-go:
	"$(GO)" run ./scripts/repo-check

unit:
	"$(GO)" test ./pkg/syntax ./pkg/lexer ./pkg/parser ./pkg/frontend ./pkg/project ./stdlib ./pkg/checker ./pkg/runtime ./pkg/tooling/... ./scripts/repo-check

stdlib-check:
	"$(GO)" test ./tests/e2e -run '^TestStandardLibrarySources$$'

stdlib-test: build stdlib-check
	./ms run scripts/conformance.ms -- "$(CURDIR)/ms" stdlib 0 1

conformance: build
	./ms test scripts/conformance.ms
	./ms run scripts/conformance.ms -- "$(CURDIR)/ms" "$(CONFORMANCE_SUITE)" "$(CONFORMANCE_SHARD)" "$(CONFORMANCE_SHARDS)"

# Re-checks the frozen expectations against the Go oracle that recorded them (local only; CI gates on conform-rust).
# CONFORM_SHARD=i/n splits the run; see tests/conformance/README.md.
CONFORM_SHARD ?= 0/1
conform-oracle: build
	cargo run -q -p ms-conform -- lint
	cargo run -q -p ms-conform -- run --ms "$(CURDIR)/ms" --shard "$(CONFORM_SHARD)" --quiet --markdown .artifacts/conform-oracle.md

# The run, check and test phases of the corpus against the Rust `ms` (cargo build -p ms-cli), excluding fixtures whose
# answer depends on aliasing; known differences are listed in tests/conformance/rust-expect-fail.txt.
# The recorded expectations are frozen: they are the contract, and this is the corpus gate. CONFORM_SHARD=i/n splits the run.
conform-rust:
	cargo build -q -p ms-cli -p ms-conform
	target/debug/ms-conform lint
	target/debug/ms-conform run --ms target/debug/ms --phase run,check,test --exclude-tag aliasing --expect-fail tests/conformance/rust-expect-fail.txt --shard "$(CONFORM_SHARD)" --quiet --markdown .artifacts/conform-rust.md

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
.build-payload.tar.gz: .go-version go.mod $(wildcard scripts/mktoolchain/*.go internal/devtool/*.go pkg/runtime/*.go) | toolchain
	CGO_ENABLED=0 "$(GO)" run ./scripts/mktoolchain "$(CURDIR)/toolchain/go" .build-payload.tar.gz $$("$(GO)" env GOHOSTOS) $$("$(GO)" env GOHOSTARCH)

build: payload
	CGO_ENABLED=0 "$(GO)" build -trimpath -mod=vendor -tags exp.winarm64 -o ms ./cmd/ms

test: conformance
	"$(GO)" test ./...

agent-bench-check: build
	PATH="$(CURDIR):$$PATH" python3 bench/agent/run.py oracle
	python3 -m unittest discover -s bench/agent/tests

stdlib-bench: build
	bench/perf/stdlib-bench.sh $(BENCHREPEATS) $(BENCHFILTER)

e2e: conformance
	"$(GO)" test $(E2EFLAGS) ./tests/e2e

race:
	"$(GO)" test -race $$(cat scripts/race-packages)

coverage: conformance
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

# The Rust docgen (crates/ms-guide). docs-parity proves it writes exactly the files the Go
# docgen writes, byte for byte, for the book tree and the API downloads.
docs-rs:
	cargo run -q -p ms-guide --bin ms-docgen

docs-check-rs:
	cargo run -q -p ms-guide --bin ms-docgen -- -check

docs-parity:
	"$(GO)" run ./scripts/docgen
	rm -rf .artifacts/docs-rs .artifacts/docs-rs-static
	cargo run -q -p ms-guide --bin ms-docgen -- -artifacts .artifacts/docs-rs -static .artifacts/docs-rs-static
	diff -r .artifacts/docs .artifacts/docs-rs
	diff website/static/stdlib.md .artifacts/docs-rs-static/stdlib.md
	diff website/static/stdlib.json .artifacts/docs-rs-static/stdlib.json

book: docs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir

book-check: docs-check docs
	node --test tests/docs/highlighting.test.cjs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir --destination "$(BOOK_CHECK_DIR)" --baseURL "https://example.org/manuscript/"
	MANUSCRIPT_BOOK_DIR="$(BOOK_CHECK_DIR)" node --test tests/docs/publication.test.cjs

vendor-refresh:
	"$(GO)" run ./scripts/maintenance vendor
