HUGO ?= hugo
VSCODE_CLI ?= code
RELEASE_MS ?= $(CURDIR)/target/release/ms
C_MS ?= $(CURDIR)/.artifacts/build/ci/src/driver/ms-c
# The ms that runs the repository tools in tools/ (`make build-rust` produces it).
MS ?= $(RELEASE_MS)
BENCHREPEATS ?= 5
BENCHFILTER ?=
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation
CONFORM_SHARD ?= 0/1

.PHONY: build build-rust bench-gate runtime doctor verify verify-full check repo-check unit test conform conform-llvm drift-check poison-check view-matrix ownership-fuzz llvm-report leak-check cancel-sweep perf-counts scaling-check count-check resource-matrix close-matrix copy-check removed-check fmt licenses licenses-check docs docs-check docs-coverage book book-check dist dist-check agent-bench-check bench-check stdlib-bench vscode-package vscode-install

doctor: build-rust
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

verify-full: verify conform removed-check book-check dist-check

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

unit: runtime
	cargo nextest run --workspace
	cargo test --workspace --doc
	node --test tests/diagram/*.test.cjs

test: unit conform

# The C compiler: configures and builds the `ci` preset (src/README.md); `ms-c` lands in $(C_MS).
build:
	cmake --preset ci
	cmake --build --preset ci

# The frozen Rust `ms` that the remaining Rust-based targets run until they are ported.
build-rust: runtime
	cargo build --release --locked -p ms-cli

# The frozen conformance corpus against the Rust `ms`, every phase, with programs built by Cranelift (about 3x
# faster than LLVM; see documentation/contributing/development.md). Excludes fixtures whose answer depends on
# aliasing; known differences are listed in tests/conformance/expect-fail.txt. CONFORM_SHARD=i/n splits the run.
conform: build-rust
	CONFORM_FAST=1 MS_BACKEND=cranelift $(MS) run tools/conform.ms

# The same corpus with programs built by LLVM (Release), as CI runs on main and on pull requests that touch
# LLVM-related code. Run it after changing LLVM code. It runs on `target/debug/ms`, so that is rebuilt first.
conform-llvm: build-rust
	cargo build --locked -p ms-cli
	$(MS) run tools/conform.ms

# Release build time, IR size, direct-emission share and kernel times of the LLVM backend against Cranelift.
llvm-report: build-rust
	MS=$(MS) $(MS) run tools/llvm-direct-check.ms -- report

# Backend drift: the run and test phases of the corpus under LLVM (Release default) and under Cranelift
# (MS_BACKEND=cranelift), compared directly; any differing stdout, stderr or exit status fails.
drift-check: build-rust
	cargo build --release --locked -q -p ms-conform
	target/release/ms-conform diff --a target/release/ms --b target/release/ms --env-b MS_BACKEND=cranelift --phase run,test --quiet

# The corpus under both backends with every dead statement stack slot filled with a pattern (MS_POISON_SLOTS=1), so a
# pointer that outlives its slot fails in every build, not only where the backend happens to reuse the slot.
poison-check: build-rust
	cargo build --locked -p ms-cli
	MS_POISON_SLOTS=1 $(MS) run tools/conform.ms
	CONFORM_FAST=1 MS_BACKEND=cranelift MS_POISON_SLOTS=1 $(MS) run tools/conform.ms

# Generates a program per view operation, way of holding the text and set of later temporaries, runs each in Debug and Release with dead slots poisoned, and fails when a view prints anything but its expected text. Nightly on main.
view-matrix: build-rust
	$(MS) run tools/view-matrix.ms

# Writes random programs mixing moves, borrows, closures and temporaries, runs the ones the checker accepts in Debug and Release on the counting runtime, and fails on a crash, a wrong or differing print, or a leaked block. SEED and COUNT pick the run. Nightly on main.
ownership-fuzz: build-rust
	$(MS) run tools/ownership-fuzz.ms -- $(or $(SEED),1) $(or $(COUNT),300)

# Runs corpus programs against a runtime that counts live heap blocks and fails on any block left at exit.
count-check: build-rust
	$(MS) run tools/count-check.ms
	MS=$(MS) $(MS) run tools/count-check-selftest.ms

# Instructions executed by the suite and guard programs under callgrind against bench/perf/counts.txt; fails when one is over 3% higher.
perf-counts: build-rust
	$(MS) run tools/perf-counts.ms

# Generated inputs at 1k/10k/100k units; fails when the 100k/10k time ratio of linear work exceeds SCALING_BOUND.
scaling-check: build-rust
	$(MS) run tools/scaling-check.ms

leak-check: build-rust
	$(MS) run tools/leak-check.ms

# Runs the e2e stdlib tests with MS_SCHED_STRESS=1 (a promise never starts on its creator; the first idle thread takes it) and fails on a file that passes without it. Only a runtime built with the sched-stress feature has the mode, so this builds a separate `ms` (target/stress) that embeds it and runs everything with that one. STRESS_CHANGED=<ref> runs only fixtures changed since <ref>. Nightly on main; not in PR CI.
stress-sched:
	cargo xtask runtime --sched-stress
	MS_NATIVE_LIB=$(CURDIR)/target/ms-native/libms_native_stress.a cargo build --release --locked -p ms-cli --target-dir target/stress
	MS=target/stress/release/ms target/stress/release/ms run tools/stress-sched.ms

# Cancels each e2e stdlib test at every park in turn and fails when cancellation leaves more blocks live than the uncancelled run.
cancel-sweep: build-rust
	$(MS) run tools/cancel-sweep.ms

# Generates a program per resource operation, call form and argument form; each one the checker accepts must close every resource it made once.
resource-matrix: build-rust
	$(MS) run tools/resource-matrix.ms

# Generates a program per resource shape and language construct (scope end, early exits, loops, moves, generics, closures, promises, cancellation); each one the checker accepts must close every resource it made once.
close-matrix: build-rust
	$(MS) run tools/close-matrix.ms

copy-check: build-rust
	$(MS) run tools/copy-check.ms

# Every removed or renamed spelling in tests/removed/ must fail `ms check` with an error that names its replacement.
removed-check: build-rust
	$(MS) run tools/removed-check.ms

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

# BOOK_BASEURL moves the site to another address, as a release's archived copy under versions/v<version>/.
book: docs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir $(if $(BOOK_BASEURL),--baseURL "$(BOOK_BASEURL)")

book-check: docs-check docs
	node --test tests/docs/highlighting.test.cjs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir --destination "$(BOOK_CHECK_DIR)" --baseURL "https://example.org/manuscript/"
	MANUSCRIPT_BOOK_DIR="$(BOOK_CHECK_DIR)" node --test tests/docs/publication.test.cjs

dist: build-rust
	$(MS) run tools/package.ms

# Extracts the archive for this host and runs the packaged binary on the hello example.
dist-check: dist
	$(MS) run tools/dist-check.ms

agent-bench-check: build-rust
	PATH="$(dir $(RELEASE_MS)):$$PATH" "$(RELEASE_MS)" run bench/agent/run.ms -- oracle
	"$(RELEASE_MS)" test bench/agent/core_test.ms

# Runs bench/perf/guards as `ms bench --ops` and fails when a work count (MIR operations, allocations, bytes allocated, copies) rose more than 3% over baseline.json. Counts do not depend on machine load or host, so unlike times they can gate; callgrind (`perf-counts`) stays for the Rust crates.
bench-gate: build-rust
	$(RELEASE_MS) bench bench/perf/guards/ms.toml --ops --baseline bench/perf/guards/baseline.json --fail-over 3

# Type-checks every benchmark project and standalone bench source so the suites cannot rot unnoticed.
bench-check: build-rust
	@for t in $$(find bench/perf -name ms.toml | sort); do \
		(cd $$(dirname $$t) && "$(RELEASE_MS)" check ms.toml) || exit 1; \
	done
	@for f in $$(find bench/perf -name '*.ms' -not -path 'bench/perf/formatter-flow/*' -not -path 'bench/perf/results/*' | sort); do \
		p=$$(dirname $$f); \
		while [ $$p != bench/perf ] && [ ! -f $$p/ms.toml ]; do p=$$(dirname $$p); done; \
		[ -f $$p/ms.toml ] || "$(RELEASE_MS)" check $$f || exit 1; \
	done
	@for t in bench/tools/*.ms bench/agent/*.ms; do "$(RELEASE_MS)" check $$t || exit 1; done
	@for t in bench/tools/*_test.ms; do "$(RELEASE_MS)" test $$t || exit 1; done

# Runs the bench blocks of bench/perf/stdlib; BENCHREPEATS is the sample count per case.
stdlib-bench: build-rust
	MS="$(RELEASE_MS)" "$(RELEASE_MS)" run bench/tools/stdlib_bench.ms -- $(BENCHREPEATS) $(BENCHFILTER)
