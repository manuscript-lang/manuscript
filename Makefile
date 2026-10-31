HUGO ?= hugo
VSCODE_CLI ?= code
RELEASE_MS ?= $(CURDIR)/target/release/ms
# The ms that runs the repository tools in tools/ (`make build` produces it).
MS ?= $(RELEASE_MS)
BENCHREPEATS ?= 5
BENCHFILTER ?=
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation
CONFORM_SHARD ?= 0/1

.PHONY: runtime doctor verify verify-full check repo-check unit test build conform e2e leak-check count-check fmt licenses licenses-check docs docs-check docs-coverage book book-check dist dist-check agent-bench-check bench-check stdlib-bench vscode-package vscode-install

doctor: build
	HUGO="$(HUGO)" $(MS) run tools/doctor.ms

# Use the locked editor dependencies; packaging runs the extension checks and bundle.
vscode-package:
	cd extensions/vscode && npm ci && npm run package

vscode-install: vscode-package
	@command -v "$(VSCODE_CLI)" >/dev/null 2>&1 || { echo 'VS Code CLI not found; add code to PATH or set VSCODE_CLI=/path/to/code.' >&2; exit 1; }
	@vsix=$$(node -p 'const p = require("./extensions/vscode/package.json"); "extensions/vscode/" + p.name + "-" + p.version + ".vsix"') && \
		"$(VSCODE_CLI)" --install-extension "$$vsix" --force

# Routine feedback excludes native distributions. The merge gate adds the conformance corpus and the book.
verify: check repo-check bench-check unit docs-check licenses-check

verify-full: verify conform e2e book-check dist-check

# Builds the native runtime (ms-native) into target/ms-native; every build of ms-cli embeds it.
runtime:
	cargo xtask runtime

check: runtime
	cargo fmt --all --check
	cargo clippy --workspace --all-targets -- -D warnings

fmt:
	cargo fmt --all

# Nested matches, .ms formatting, stdlib syntax, release pins, workflow triggers, Rust unsafe allow-list.
repo-check:
	cargo run --release --locked -q -p ms-repo-check

unit: runtime
	cargo nextest run --workspace
	cargo test --workspace --doc

test: unit conform

build: runtime
	cargo build --release --locked -p ms-cli

# The run, check and test phases of the frozen conformance corpus against the Rust `ms`, excluding fixtures whose
# answer depends on aliasing; known differences are listed in tests/conformance/expect-fail.txt.
# CONFORM_SHARD=i/n splits the run.
conform: build
	$(MS) run tools/conform.ms

# Every `tests/e2e/testdata` fixture: accept fixtures pass `ms test`, reject fixtures fail `ms check`.
# E2E_BUILD_TYPE picks the build type (default Release).
e2e: build
	$(MS) run tools/e2e.ms

# Runs corpus programs against a runtime that counts live heap blocks and fails on any block left at exit.
count-check: build
	$(MS) run tools/count-check.ms

leak-check: build
	$(MS) run tools/leak-check.ms

# The dependency license inventory: crate licenses from cargo metadata plus bundled notice hashes.
licenses:
	cargo run --release --locked -q -p ms-repo-check -- licenses

licenses-check:
	cargo run --release --locked -q -p ms-repo-check -- licenses -check

# The book and API reference come from the Rust docgen (crates/ms-tooling).
docs:
	cargo run -q --release --locked -p ms-tooling --bin ms-docgen

docs-check:
	cargo run -q --release --locked -p ms-tooling --bin ms-docgen -- -check

docs-coverage:
	cargo run -q --release --locked -p ms-tooling --bin ms-docgen -- -check -coverage .artifacts/stdlib-doc-coverage.json

book: docs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir

book-check: docs-check docs
	node --test tests/docs/highlighting.test.cjs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir --destination "$(BOOK_CHECK_DIR)" --baseURL "https://example.org/manuscript/"
	MANUSCRIPT_BOOK_DIR="$(BOOK_CHECK_DIR)" node --test tests/docs/publication.test.cjs

dist: build
	$(MS) run tools/package.ms

# Extracts the archive for this host and runs the packaged binary on the hello example.
dist-check: dist
	$(MS) run tools/dist-check.ms

agent-bench-check: build
	PATH="$(dir $(RELEASE_MS)):$$PATH" python3 bench/agent/run.py oracle
	python3 -m unittest discover -s bench/agent/tests

# Type-checks every benchmark project so the suites cannot rot unnoticed.
bench-check: build
	@for t in $$(find bench/perf -name ms.toml | sort); do \
		(cd $$(dirname $$t) && "$(RELEASE_MS)" check ms.toml) || exit 1; \
	done
	@for t in bench/tools/*.ms; do "$(RELEASE_MS)" check $$t || exit 1; done
	@for t in bench/tools/*_test.ms; do "$(RELEASE_MS)" test $$t || exit 1; done

# Runs the bench blocks of bench/perf/stdlib; BENCHREPEATS is the sample count per case.
stdlib-bench: build
	MS="$(RELEASE_MS)" "$(RELEASE_MS)" run bench/tools/stdlib_bench.ms -- $(BENCHREPEATS) $(BENCHFILTER)
