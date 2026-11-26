HUGO ?= hugo
VSCODE_CLI ?= code
# The ms that runs the repository tools in tools/ (`make build` produces it).
MS ?= $(CURDIR)/.artifacts/build/ci/src/cli/ms
BENCHREPEATS ?= 5
BENCHFILTER ?=
GROUP ?= all
SAMPLES ?= 5
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation

# Formatting, nested matches (.ms and Markdown fences), release pins, workflow triggers and the license inventory
# (tools/repo-check.ms; `make licenses` rewrites the inventory).
repo-check: build
	cmake --build --preset ci --target repo-check

licenses: build
	$(MS) run tools/repo-check.ms -- licenses

licenses-check: repo-check

# Each of these runs tools/<name>.ms with the built ms; the tool's header comment says what it checks.
TOOLS := doctor view-matrix scaling-check leak-check cancel-sweep perf-counts resource-matrix close-matrix copy-check memcpy-check removed-check stress-sched

.PHONY: build conform conform-release verify verify-full repo-check licenses licenses-check docs docs-check docs-coverage book book-check dist dist-check bench-check perf perf-list perf-check stdlib-bench poison-check ownership-fuzz bench-gate count-check vscode-package vscode-install $(TOOLS)

# Configures and builds the `ci` preset (src/README.md); `ms` lands in $(MS).
build:
	cmake --preset ci
	cmake --build --preset ci
	@cmake --build --preset ci --target llvm-lib >/dev/null || echo "warning: the shared LLVM library was not fetched; ms cannot compile until it is (make llvm-lib retries)"
	@cmake --build --preset ci --target cranelift-lib >/dev/null || echo "warning: the shared Cranelift library was not fetched; Debug builds use LLVM (make cranelift-lib retries)"

# The conformance corpus replayed with the ms just built (tools/conform-run.ms).
conform: build
	cmake --build --preset ci --target conform

# The run and test phases replayed with the Release (optimizing) build; CI replays Debug, so a difference between the two
# builds of one program fails here. Nightly on main.
conform-release: build
	CONFORM_BUILD_TYPE=Release $(MS) run tools/conform-run.ms -- --phase run
	CONFORM_BUILD_TYPE=Release $(MS) run tools/conform-run.ms -- --phase test

# Routine feedback; the merge gate adds the conformance corpus, removed spellings, the book and the package.
verify: repo-check bench-check docs-check licenses-check

verify-full: verify conform removed-check book-check dist-check

$(TOOLS): build
	HUGO="$(HUGO)" $(MS) run tools/$@.ms

# The corpus with every dead statement slot poisoned (MS_POISON_SLOTS=1), under the default build type.
# The corpus with dead stack cells filled with 0xDD (the compiler reads MS_POISON_SLOTS): a view that outlives its slot
# prints garbage in every build.
poison-check: build
	MS_POISON_SLOTS=1 cmake --build --preset ci --target conform

# The allocation and copy counts of the guard programs against bench/perf/guards/baseline.json; fails when one rose more than
# 3%. Nightly on main.
bench-gate: build
	cd bench/perf/guards && "$(MS)" bench ms.toml --baseline baseline.json --fail-over 3

# Random ownership programs; SEED and COUNT pick the run. Nightly on main.
ownership-fuzz: build
	$(MS) run tools/ownership-fuzz.ms -- $(or $(SEED),1) $(or $(COUNT),300)

count-check: build
	$(MS) run tools/count-check.ms
	MS=$(MS) $(MS) run tools/count-check-selftest.ms

dist: build
	cmake --build --preset ci --target dist

# Extracts the archive for this host and runs the packaged binary on the hello example.
dist-check: build
	cmake --build --preset ci --target dist-smoke

# Use the locked editor dependencies; packaging runs the extension checks and bundle.
vscode-package:
	cd extensions/vscode && npm ci && npm run package

vscode-install: vscode-package
	@command -v "$(VSCODE_CLI)" >/dev/null 2>&1 || { echo 'VS Code CLI not found; add code to PATH or set VSCODE_CLI=/path/to/code.' >&2; exit 1; }
	@vsix=$$(node -p 'const p = require("./extensions/vscode/package.json"); "extensions/vscode/" + p.name + "-" + p.version + ".vsix"') && \
		"$(VSCODE_CLI)" --install-extension "$$vsix" --force

# The API reference, its downloads and the description coverage come from tools/docgen.ms, which reads `ms dev doc`.
docs: build
	MS="$(MS)" $(MS) run tools/docgen.ms

docs-check: build
	cmake --build --preset ci --target docs-check

docs-coverage: build
	MS="$(MS)" $(MS) run tools/docgen.ms -- --check --coverage .artifacts/stdlib-doc-coverage.json

# BOOK_BASEURL moves the site to another address, as a release's archived copy under versions/v<version>/.
book: docs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir $(if $(BOOK_BASEURL),--baseURL "$(BOOK_BASEURL)")

book-check: docs-check docs
	node --test tests/docs/highlighting.test.cjs
	"$(HUGO)" --source website --minify --panicOnWarning --cleanDestinationDir --destination "$(BOOK_CHECK_DIR)" --baseURL "https://example.org/manuscript/"
	MANUSCRIPT_BOOK_DIR="$(BOOK_CHECK_DIR)" node --test tests/docs/publication.test.cjs

bench-check: build
	@for t in $$(find bench/perf -name ms.toml | sort); do \
		(cd $$(dirname $$t) && "$(MS)" check --only types ms.toml) || exit 1; \
	done
	@for f in $$(find bench/perf -name '*.ms' | sort); do \
		p=$$(dirname $$f); \
		while [ $$p != bench/perf ] && [ ! -f $$p/ms.toml ]; do p=$$(dirname $$p); done; \
		[ -f $$p/ms.toml ] || "$(MS)" check --only types $$f || exit 1; \
	done
	@for t in bench/perf/tools/*.ms bench/agent/*.ms; do "$(MS)" check --only types $$t || exit 1; done
	@for t in bench/agent/challenges/*/start/ms/src/main.ms; do "$(MS)" check --only types $$t || exit 1; done
	@for t in bench/perf/tools/*_test.ms; do "$(MS)" test $$t || exit 1; done
	@"$(MS)" run bench/perf/tools/perf.ms -- check

# The performance suite (bench/perf/groups.txt): `make perf GROUP=<group|time|count> SAMPLES=5` runs a group, `perf-list` names them.
perf: build
	MS="$(abspath $(MS))" "$(MS)" run bench/perf/tools/perf.ms -- run $(GROUP) $(SAMPLES)

perf-list: build
	"$(MS)" run bench/perf/tools/perf.ms -- list

perf-check: build
	"$(MS)" run bench/perf/tools/perf.ms -- check

# Runs the bench blocks of bench/perf/stdlib; BENCHREPEATS is the sample count per case.
stdlib-bench: build
	MS="$(MS)" "$(MS)" run bench/perf/tools/stdlib_bench.ms -- $(BENCHREPEATS) $(BENCHFILTER)
