HUGO ?= hugo
VSCODE_CLI ?= code
# The ms that runs the repository tools in tools/ (`make build` produces it).
MS ?= $(CURDIR)/.artifacts/build/ci/src/driver/ms-c
RELEASE_MS ?= $(MS)
BENCHREPEATS ?= 5
BENCHFILTER ?=
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation

.PHONY: build doctor verify verify-full repo-check conform poison-check view-matrix ownership-fuzz llvm-report leak-check cancel-sweep perf-counts scaling-check count-check resource-matrix close-matrix copy-check removed-check licenses licenses-check docs docs-check docs-coverage book book-check dist dist-check bench-check stdlib-bench vscode-package vscode-install

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
verify: repo-check bench-check docs-check licenses-check

verify-full: verify conform removed-check book-check dist-check

# Nested matches, .ms formatting, stdlib syntax, release pins, workflow triggers, Rust unsafe allow-list.
repo-check:
	cargo run --release --locked -q -p ms-repo-check

# Builds ms: configures and builds the `ci` preset (src/README.md); `ms-c` lands in $(MS).
build:
	cmake --preset ci
	cmake --build --preset ci

# The conformance corpus replayed with the ms just built (tools/conform-run.ms).
conform: build
	cmake --build --preset ci --target conform

# Release build time, IR size, direct-emission share and kernel times of the LLVM backend against Cranelift.
llvm-report: build
	MS=$(MS) $(MS) run tools/llvm-direct-check.ms -- report

# The corpus under both backends with every dead statement stack slot filled with a pattern (MS_POISON_SLOTS=1), so a
# pointer that outlives its slot fails in every build, not only where the backend happens to reuse the slot.
poison-check: build
	MS_POISON_SLOTS=1 $(MS) run tools/conform.ms
	CONFORM_FAST=1 MS_BACKEND=cranelift MS_POISON_SLOTS=1 $(MS) run tools/conform.ms

# Generates a program per view operation, way of holding the text and set of later temporaries, runs each in Debug and Release with dead slots poisoned, and fails when a view prints anything but its expected text. Nightly on main.
view-matrix: build
	$(MS) run tools/view-matrix.ms

# Writes random programs mixing moves, borrows, closures and temporaries, runs the ones the checker accepts in Debug and Release on the counting runtime, and fails on a crash, a wrong or differing print, or a leaked block. SEED and COUNT pick the run. Nightly on main.
ownership-fuzz: build
	$(MS) run tools/ownership-fuzz.ms -- $(or $(SEED),1) $(or $(COUNT),300)

# Runs corpus programs against a runtime that counts live heap blocks and fails on any block left at exit.
count-check: build
	$(MS) run tools/count-check.ms
	MS=$(MS) $(MS) run tools/count-check-selftest.ms

# Instructions executed by the suite and guard programs under callgrind against bench/perf/counts.txt; fails when one is over 3% higher.
perf-counts: build
	$(MS) run tools/perf-counts.ms

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

# Every removed or renamed spelling in tests/removed/ must fail `ms check` with an error that names its replacement.
removed-check: build
	$(MS) run tools/removed-check.ms

# Rust tools kept until they are ported to Manuscript (#6380): repo-check, licenses, docs.
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

dist: build
	$(MS) run tools/package.ms

# Extracts the archive for this host and runs the packaged binary on the hello example.
dist-check: dist
	$(MS) run tools/dist-check.ms

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
	@for t in bench/tools/*.ms bench/agent/*.ms; do "$(RELEASE_MS)" check $$t || exit 1; done
	@for t in bench/tools/*_test.ms; do "$(RELEASE_MS)" test $$t || exit 1; done

# Runs the bench blocks of bench/perf/stdlib; BENCHREPEATS is the sample count per case.
stdlib-bench: build
	MS="$(RELEASE_MS)" "$(RELEASE_MS)" run bench/tools/stdlib_bench.ms -- $(BENCHREPEATS) $(BENCHFILTER)
