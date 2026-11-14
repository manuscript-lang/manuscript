HUGO ?= hugo
VSCODE_CLI ?= code
RELEASE_MS ?= $(CURDIR)/target/release/ms
# The ms that runs the repository tools in tools/ (`make build` produces it).
MS ?= $(RELEASE_MS)
BENCHREPEATS ?= 5
BENCHFILTER ?=
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation
CONFORM_SHARD ?= 0/1

.PHONY: runtime doctor verify verify-full check repo-check workflow-check unit test build conform conform-fast drift-check llvm-report leak-check cancel-sweep scaling-check count-check resource-matrix close-matrix copy-check fmt licenses licenses-check docs docs-check docs-coverage book book-check dist dist-check agent-bench-check bench-check stdlib-bench vscode-package vscode-install

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
verify: check repo-check workflow-check bench-check unit docs-check licenses-check

verify-full: verify conform book-check dist-check

# Builds the native runtime (ms-native) into target/ms-native; every build of ms-cli embeds it.
runtime:
	cargo xtask runtime

check: runtime
	cargo xtask symbols --check
	cargo fmt --all --check
	cargo clippy --workspace --all-targets -- -D warnings

fmt:
	cargo fmt --all

# Nested matches, .ms formatting, stdlib syntax, release pins, workflow triggers, Rust unsafe allow-list.
repo-check:
	cargo run --release --locked -q -p ms-repo-check

workflow-check:
	node --test tests/workflows/*.test.cjs

unit: runtime
	cargo nextest run --workspace
	cargo test --workspace --doc
	node --test tests/diagram/*.test.cjs

test: unit conform

build: runtime
	cargo build --release --locked -p ms-cli

# The run, check and test phases of the frozen conformance corpus against the Rust `ms`, excluding fixtures whose
# answer depends on aliasing; known differences are listed in tests/conformance/expect-fail.txt.
# CONFORM_SHARD=i/n splits the run.
conform: build
	$(MS) run tools/conform.ms

# The quick local loop: every phase, with programs built by Cranelift (about 3x faster than LLVM; see
# documentation/contributing/development.md). CI still runs the LLVM pass; run `make conform` before merging.
conform-fast: build
	CONFORM_FAST=1 MS_BACKEND=cranelift $(MS) run tools/conform.ms

# Release build time, IR size, direct-emission share and kernel times of the LLVM backend against Cranelift.
llvm-report: build
	MS=$(MS) $(MS) run tools/llvm-direct-check.ms -- report

# Backend drift: the run and test phases of the corpus under LLVM (Release default) and under Cranelift
# (MS_BACKEND=cranelift), compared directly; any differing stdout, stderr or exit status fails.
drift-check: build
	cargo build --release --locked -q -p ms-conform
	target/release/ms-conform diff --a target/release/ms --b target/release/ms --env-b MS_BACKEND=cranelift --phase run,test --quiet

# Runs corpus programs against a runtime that counts live heap blocks and fails on any block left at exit.
count-check: build
	$(MS) run tools/count-check.ms
	MS=$(MS) $(MS) run tools/count-check-selftest.ms

# Generated inputs at 1k/10k/100k units; fails when the 100k/10k time ratio of linear work exceeds SCALING_BOUND.
scaling-check: build
	$(MS) run tools/scaling-check.ms

leak-check: build
	$(MS) run tools/leak-check.ms

# Cancels each e2e stdlib test at every park in turn and fails when cancellation leaves more blocks live than the uncancelled run.
cancel-sweep: build
	$(MS) run tools/cancel-sweep.ms

# Generates a program per resource operation, call form and argument form; each one the checker accepts must close every resource it made once.
resource-matrix: build
	$(MS) run tools/resource-matrix.ms

# Generates a program per resource shape and language construct (scope end, early exits, loops, moves, generics, closures, promises, cancellation); each one the checker accepts must close every resource it made once.
close-matrix: build
	$(MS) run tools/close-matrix.ms

copy-check: build
	$(MS) run tools/copy-check.ms

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
	PATH="$(dir $(RELEASE_MS)):$$PATH" "$(RELEASE_MS)" run bench/agent/run.ms -- oracle
	"$(RELEASE_MS)" test bench/agent/core_test.ms

# Type-checks every benchmark project and standalone bench source so the suites cannot rot unnoticed.
bench-check: build
	@for t in $$(find bench/perf -name ms.toml | sort); do \
		(cd $$(dirname $$t) && "$(RELEASE_MS)" check ms.toml) || exit 1; \
	done
	@for f in $$(find bench/perf -name '*.ms' -not -path 'bench/perf/formatter-flow/*' -not -path 'bench/perf/results/*' | sort); do \
		p=$$(dirname $$f); \
		while [ $$p != bench/perf ] && [ ! -f $$p/ms.toml ]; do p=$$(dirname $$p); done; \
		[ -f $$p/ms.toml ] || "$(RELEASE_MS)" check $$f || exit 1; \
	done
	@for t in bench/tools/*.ms; do "$(RELEASE_MS)" check $$t || exit 1; done
	@for t in bench/tools/*_test.ms; do "$(RELEASE_MS)" test $$t || exit 1; done

# Runs the bench blocks of bench/perf/stdlib; BENCHREPEATS is the sample count per case.
stdlib-bench: build
	MS="$(RELEASE_MS)" "$(RELEASE_MS)" run bench/tools/stdlib_bench.ms -- $(BENCHREPEATS) $(BENCHFILTER)
