HUGO ?= hugo
VSCODE_CLI ?= code
RELEASE_MS ?= $(CURDIR)/target/release/ms
# The ms that runs the repository tools in tools/ (`make build` produces it).
MS ?= $(RELEASE_MS)
BENCHREPEATS ?= 5
BENCHFILTER ?=
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation
CONFORM_SHARD ?= 0/1

.PHONY: setup lsp-test rebuild libms-tools bench-gate runtime doctor verify verify-full check repo-check workflow-check unit test build conform conform-llvm poison-check view-matrix ownership-fuzz llvm-report leak-check cancel-sweep perf-counts scaling-check count-check resource-matrix close-matrix copy-check removed-check ms-cli-check fmt licenses licenses-check docs docs-model docs-check docs-coverage book book-check dist dist-check agent-bench-check bench-check stdlib-bench c-test c-compiler-test c-driver-test vscode-package vscode-install c-fuzz c-tools-test

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
verify: check repo-check c-lint workflow-check bench-check lsp-test unit docs-check licenses-check

verify-full: verify conform removed-check ms-cli-check book-check dist-check

# Installs what the C build needs (CMake, Ninja, clang, musl-gcc, perl and the system libraries); run once on a new machine.
setup:
	sh src/runtime/third_party/libs.sh install

# Builds the native C runtime into target/ms-native; every build of ms-cli embeds it. A missing tool is named first,
# with `make setup`, rather than failing inside CMake.
runtime:
	sh src/runtime/third_party/libs.sh check
	cmake -P cmake/BuildRuntime.cmake

check: build
	"$(RELEASE_MS)" run src/ms/symbols.ms -- --check
	cargo fmt --all --check
	cargo clippy --workspace --all-targets -- -D warnings

fmt:
	cargo fmt --all

# The libms entry points that Manuscript tools call with `extern fn` (src/compiler/tools/tool_shim.c).
libms-tools:
	cmake -S . -B target/cmake/tools -G Ninja -DMS_BUILD_RUNTIME=OFF
	cmake --build target/cmake/tools --target ms_tools_shim
	cp target/cmake/tools/compiler/libms_tools.a target/libms_tools.a

# Nested matches, .ms formatting, stdlib syntax, release pins, workflow triggers, portability and
# the other rules in tools/repo-check/, written in Manuscript over libms.
repo-check: build libms-tools
	$(MS) run tools/repo-check.ms --link target/libms_tools.a

workflow-check:
	node --test tests/workflows/*.test.cjs

unit: runtime
	cargo nextest run --workspace
	cargo test --workspace --doc
	node --test tests/diagram/*.test.cjs

test: unit conform

# The old binary is removed first and its presence checked after, so a failed build never leaves a stale `ms` that later
# commands run (a stale ms gives wrong census and conformance answers).
build: runtime
	@rm -f "$(RELEASE_MS)"
	cargo build --release --locked -p ms-cli
	@test -x "$(RELEASE_MS)" || { echo "make build: $(RELEASE_MS) was not produced" >&2; exit 1; }

# A clean rebuild from the sources: drops the built C libraries, every CMake cache and the runtime archive, the
# repository tools' shim and the old ms, then builds again. Downloaded LLVM and lld tools and cargo's own cache stay.
rebuild:
	rm -rf target/c-libs target/ms-native target/cmake target/libms_tools.a
	rm -f "$(RELEASE_MS)"
	$(MAKE) build

# The frozen conformance corpus against the Rust `ms`, every phase, on the release `ms` that `make build` produced.
# Excludes fixtures whose answer depends on
# aliasing; known differences are listed in tests/conformance/expect-fail.txt. CONFORM_SHARD=i/n splits the run.
conform: build
	CONFORM_FAST=1 $(MS) run tools/conform.ms

# The same corpus with programs built by LLVM (Release), as CI runs on main and on pull requests that touch
# LLVM-related code. Run it after changing LLVM code. It runs on `target/debug/ms`, so that is rebuilt first.
conform-llvm: build
	cargo build --locked -p ms-cli
	$(MS) run tools/conform.ms

# Release build time, IR size, direct-emission share and kernel times of the LLVM backend.
llvm-report: build
	MS=$(MS) $(MS) run tools/llvm-direct-check.ms -- report

# The corpus with every dead statement stack slot filled with a pattern (MS_POISON_SLOTS=1), so a
# pointer that outlives its slot fails in every build, not only where the backend happens to reuse the slot.
poison-check: build
	cargo build --locked -p ms-cli
	MS_POISON_SLOTS=1 $(MS) run tools/conform.ms

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

# Runs the e2e stdlib tests with MS_SCHED_STRESS=1 (a promise never starts on its creator; the first idle thread takes it) and fails on a file that passes without it. Every runtime has the mode. STRESS_CHANGED=<ref> runs only fixtures changed since <ref>. Nightly on main; not in PR CI.
stress-sched: build
	$(MS) run tools/stress-sched.ms

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

# The Manuscript command-line front (src/ms) against the Rust ms on the argument lines in src/ms/cases.txt.
ms-cli-check: build target/c-tool/libmstool.a
	$(MS) run tools/ms-cli-check.ms

# The dependency license inventory: crate licenses from cargo metadata plus bundled notice hashes.
licenses: build libms-tools
	$(MS) run tools/repo-check.ms --link target/libms_tools.a -- licenses

licenses-check: build libms-tools
	$(MS) run tools/repo-check.ms --link target/libms_tools.a -- licenses -check

# The book and API reference come from the C checker's API model (ms_api_model) through src/ms/docgen.ms; the
# description policy is checked by src/ms/doc_inventory.ms.
DOC_MODEL = target/c-tool/model.json

docs-model: target/c-tool/libmstool.a
	target/c-tool/ms_api_model src/stdlib > $(DOC_MODEL)

# Rebuilds the disposable book Markdown (.artifacts/docs) and the API downloads (website/static/stdlib.*).
docs: docs-model docs-check
	rm -rf target/c-tool/docs target/c-tool/docs.out .artifacts/docs
	$(RELEASE_MS) run src/ms/docgen.ms -- $(DOC_MODEL) target/c-tool/docs.out
	mkdir -p .artifacts/docs website/static
	cp -r target/c-tool/docs.out/documentation .artifacts/docs/
	cp target/c-tool/docs.out/website/static/stdlib.md target/c-tool/docs.out/website/static/stdlib.json website/static/

# Validates the API descriptions against the policy; fails on a declaration that does not meet it.
docs-check: docs-model
	$(RELEASE_MS) run src/ms/doc_inventory.ms -- $(DOC_MODEL) src/ms/data/description_backlog.json

docs-coverage: docs-model
	mkdir -p .artifacts
	$(RELEASE_MS) run src/ms/doc_inventory.ms -- $(DOC_MODEL) src/ms/data/description_backlog.json .artifacts/stdlib-doc-coverage.json

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

# The language server written in Manuscript (src/lsp): its unit tests and a check of the entry point.
lsp-test: build
	"$(RELEASE_MS)" test src/lsp/frame.ms src/lsp/text.ms src/lsp/uri.ms src/lsp/structure.ms src/lsp/server.ms src/lsp/check.ms
	"$(RELEASE_MS)" check src/lsp/main.ms

agent-bench-check: build
	PATH="$(dir $(RELEASE_MS)):$$PATH" "$(RELEASE_MS)" run bench/agent/run.ms -- oracle
	"$(RELEASE_MS)" test bench/agent/core_test.ms

# Runs bench/perf/guards as `ms bench --ops` and fails when a work count (MIR operations, allocations, bytes allocated, copies) rose more than 3% over baseline.json. Counts do not depend on machine load or host, so unlike times they can gate; callgrind (`perf-counts`) stays for the Rust crates.
bench-gate: build
	$(RELEASE_MS) bench bench/perf/guards/ms.toml --ops --baseline bench/perf/guards/baseline.json --fail-over 3

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

# The C build: one CMake project (CMakeLists.txt, cmake/) for the runtime archive, its tests and the fuzz harnesses,
# generated with Ninja; ccache is used when installed. `c-configure` and `c-build` make target/cmake/test (sanitizers on).
C_BUILD ?= target/cmake/test
# The system C libraries the CMake builds find with pkg-config. Nothing is installed here: a missing one stops the
# build with the command that installs it.
.PHONY: c-deps c-configure c-build
c-deps:
	@pkg-config --exists libuv libnghttp2 libssl libcrypto libpcre2-8 zlib libcurl 2>/dev/null || { echo "make: the C libraries are not all installed (pkg-config). Install them with: sh src/runtime/third_party/libs.sh install" >&2; exit 1; }

c-configure: c-deps
	cmake -S . -B $(C_BUILD) -G Ninja -DMS_SANITIZE=ON

c-build: c-configure
	cmake --build $(C_BUILD)

# The C runtime unit tests (ctest) under AddressSanitizer and UBSan; nightly, not the pull request gate.
c-test: c-build
	ctest --test-dir $(C_BUILD) --output-on-failure -j $(shell nproc 2>/dev/null || sysctl -n hw.ncpu)

# The C style gate (documentation/contributing/c-style.md): strict warnings on every C file, clang-tidy on the
# files that differ from C_LINT_BASE (all of them when it is unset).
# Editor support for the C code: configures target/cmake/dev (no build) and links its compile_commands.json at the
# repository root, where clangd and the VS Code C/C++ extension find every include path.
.PHONY: c-ide
c-ide: c-deps
	cmake -S . -B target/cmake/dev -G Ninja
	ln -sf target/cmake/dev/compile_commands.json compile_commands.json

.PHONY: c-lint
c-lint: c-deps
	cmake -S . -B target/cmake/lint -G Ninja -DMS_BUILD_COMPILER=OFF -DMS_BUILD_TESTS=OFF
	C_LINT_BASE="$(C_LINT_BASE)" cmake --build target/cmake/lint --target c-lint

# The C runtime fuzz harnesses (src/runtime/fuzz) under AddressSanitizer and UBSan; FUZZ_RUNS, FUZZ_SEED, FUZZER=libfuzzer.
c-fuzz:
	sh src/runtime/tests/fuzz.sh

# The C compiler front end and checker against the Rust ones, byte for byte (syntax on the corpus and on mutated copies, checker tables on the standard library); nightly runs more mutants.
c-compiler-test:
	sh src/compiler/tests/syntax-diff.sh
	sh src/compiler/tests/mir-pass-frozen.sh
	sh src/compiler/tests/check-diff.sh
	sh src/compiler/tests/diag-render-diff.sh
	sh src/compiler/tests/entry-diff.sh
	sh src/compiler/tests/prelude-import-diff.sh
	sh src/compiler/tests/public-signature-diff.sh
	sh src/compiler/tests/extern-diff.sh
	sh src/compiler/tests/interface-diff.sh
	sh src/compiler/tests/param-order-diff.sh
	sh src/compiler/tests/field-defaults-diff.sh
	sh src/compiler/tests/lower-diff.sh
	sh src/compiler/tests/lower-program-diff.sh
	sh src/compiler/tests/hints-diff.sh
	sh src/compiler/tests/constfold-diff.sh
	sh src/compiler/tests/fixes-diff.sh
	sh src/compiler/tests/prelude-fix-diff.sh
	sh src/compiler/tests/import-hints-diff.sh
	sh src/compiler/tests/asm-tables.sh
	sh src/compiler/tests/llvm-run.sh
	sh src/compiler/tests/llvm-main-run.sh
	sh src/compiler/tests/data-run.sh

# libms with the tool entry points (src/compiler/include/ms/tool.h): the archive a Manuscript tool links with `--link`.
.PHONY: FORCE
FORCE:

C_TOOL = target/cmake/tools/compiler
target/c-tool/libmstool.a: FORCE
	cmake -S . -B target/cmake/tools -G Ninja -DMS_BUILD_RUNTIME=OFF
	cmake --build target/cmake/tools --target ms_tool ms_syntax_dump ms_check_dump ms_api_model
	mkdir -p target/c-tool
	cp $(C_TOOL)/libmstool.a $@
	cp $(C_TOOL)/ms_syntax_dump target/c-tool/ms_syntax_dump
	cp $(C_TOOL)/ms_api_model target/c-tool/ms_api_model

# The Manuscript tools over libms: their tests; the syntax tree read in Manuscript against the C dump over every .ms file (so the table is complete); the lexical lint against the Rust `ms lint` on mutated corpus copies; the docs generator and description inventory against `ms-docgen`; `search_symbol` against the Rust one; the `ms diagram` views and call graph against the Rust ones; and the C checker's fact dump against the Rust facts.
c-tools-test: build target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/diff.ms
	"$(RELEASE_MS)" test src/ms/mark.ms
	"$(RELEASE_MS)" test src/ms/html.ms
	"$(RELEASE_MS)" test src/ms/review_cmd.ms
	"$(RELEASE_MS)" test src/ms/diagram_cmd.ms
	"$(RELEASE_MS)" test src/ms/symbols.ms
	"$(RELEASE_MS)" test src/ms/toolchain.ms
	"$(RELEASE_MS)" test src/ms/proxy_get.ms
	"$(RELEASE_MS)" test src/ms/manifest_edit.ms
	"$(RELEASE_MS)" test src/ms/cli.ms
	"$(RELEASE_MS)" test src/ms/toml_edit_test.ms
	"$(RELEASE_MS)" test src/ms/install.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/lsp/analysis.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/lsp/navigate.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/project.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/workspace.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/text.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/matches.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/terse.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/imports.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/flow.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/test/watch.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/report.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/payloads.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/facts.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/typed.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/typed_calls.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/recursion.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/defaults.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/counter.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/flush.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/effects.ms --link target/c-tool/libmstool.a

	"$(RELEASE_MS)" test src/ms/lint/analysis.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/skill_calls.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/fixes.ms --link target/c-tool/libmstool.a
	"$(RELEASE_MS)" test src/ms/lint/interpolation.ms --link target/c-tool/libmstool.a
	git ls-files '*.ms' > target/c-tool/files.txt
	target/c-tool/ms_syntax_dump ast $$(cat target/c-tool/files.txt) | sed -E 's/^(error [0-9]+:[0-9]+:[0-9]+) .*/\1/' > target/c-tool/ast.c.txt
	"$(RELEASE_MS)" run src/ms/syntax_dump.ms --link target/c-tool/libmstool.a -- @target/c-tool/files.txt > target/c-tool/ast.ms.txt
	cmp target/c-tool/ast.c.txt target/c-tool/ast.ms.txt
	cargo run -q --release --locked -p ms-tooling --example api_model > target/c-tool/model.json
	target/c-tool/ms_api_model src/stdlib > target/c-tool/model.c.json && cmp target/c-tool/model.json target/c-tool/model.c.json
	"$(RELEASE_MS)" build src/ms/facts_entry.ms --link target/c-tool/libmstool.a -o target/c-tool/facts_entry
	mkdir -p target/c-tool/facts && cp tests/conformance/fixtures/e2e/stdlib/log.ms target/c-tool/facts/main.ms && cd target/c-tool/facts && ../facts_entry main.ms > entry.json && ../../cmake/tools/compiler/ms_check_dump ../../../src/stdlib --facts main.ms > dump.json && cmp entry.json dump.json
	rm -rf target/c-tool/proj && mkdir -p target/c-tool/proj/src && printf 'import helper from "./src/lib.ms"\n\nfn main() Int:\n\treturn helper(2)\n' > target/c-tool/proj/a.ms && printf 'export fn helper(n: Int) Int:\n\treturn n + 1\n' > target/c-tool/proj/src/lib.ms
	target/c-tool/facts_entry --project target/c-tool/proj/a.ms > target/c-tool/proj/facts.json && grep -q '"key": "a.ms#fn#main"' target/c-tool/proj/facts.json && grep -q '"key": "src/lib.ms#fn#helper"' target/c-tool/proj/facts.json && grep -q '"paths": \["./src/lib.ms"\]' target/c-tool/proj/facts.json && grep -q '"calls": \["src/lib.ms#fn#helper"\], "effects_known": true' target/c-tool/proj/facts.json
	cargo run -q --release --locked -p ms-tooling --bin ms-docgen -- -coverage target/c-tool/coverage.rust.json -artifacts target/c-tool/docs.rust -static target/c-tool/static.rust
	rm -rf target/c-tool/docs.ms
	"$(RELEASE_MS)" run src/ms/docgen.ms -- target/c-tool/model.json target/c-tool/docs.ms
	diff -r target/c-tool/docs.rust/documentation target/c-tool/docs.ms/documentation
	cmp target/c-tool/static.rust/stdlib.md target/c-tool/docs.ms/website/static/stdlib.md
	cmp target/c-tool/static.rust/stdlib.json target/c-tool/docs.ms/website/static/stdlib.json
	"$(RELEASE_MS)" run src/ms/doc_inventory.ms -- target/c-tool/model.json src/ms/data/description_backlog.json target/c-tool/coverage.ms.json
	cmp target/c-tool/coverage.rust.json target/c-tool/coverage.ms.json
	"$(RELEASE_MS)" test src/ms/doc_inventory.ms
	"$(RELEASE_MS)" build src/ms/search.ms --link target/c-tool/libmstool.a -o target/c-tool/search
	sh src/ms/search-diff.sh "$(RELEASE_MS)" target/c-tool/search
	cargo build -q --release --locked -p ms-tooling --bin ms-tooling-dev
	"$(RELEASE_MS)" build src/ms/views.ms -o target/c-tool/views
	sh src/ms/views-diff.sh target/release/ms-tooling-dev target/c-tool/views target/c-tool/views-work tests/conformance/fixtures/e2e/accept/close-error-precedence.ms tests/conformance/fixtures/e2e/stdlib/log.ms tests/conformance/fixtures/e2e/stdlib/xml.ms
	"$(RELEASE_MS)" build src/ms/review.ms -o target/c-tool/review
	"$(RELEASE_MS)" build src/ms/report.ms -o target/c-tool/report
	sh src/ms/review-diff.sh target/release/ms-tooling-dev target/c-tool/review target/c-tool/report target/c-tool/review-work tests/conformance/fixtures/e2e/accept/close-error-precedence.ms tests/conformance/fixtures/e2e/stdlib/log.ms tests/conformance/fixtures/e2e/stdlib/xml.ms
	"$(RELEASE_MS)" build src/ms/html.ms -o target/c-tool/html
	sh src/ms/html-diff.sh target/release/ms-tooling-dev target/c-tool/html target/c-tool/html-work tests/conformance/fixtures/e2e/accept/close-error-precedence.ms tests/conformance/fixtures/e2e/stdlib/log.ms tests/conformance/fixtures/e2e/stdlib/xml.ms
	"$(RELEASE_MS)" build src/ms/review_cmd.ms -o target/c-tool/review_cmd
	sh src/ms/review-cmd-diff.sh "$(RELEASE_MS)" target/c-tool/review_cmd target/release/ms-tooling-dev target/c-tool/review-cmd-work tests/conformance/fixtures/e2e/accept/close-error-precedence.ms tests/conformance/fixtures/e2e/stdlib/log.ms tests/conformance/fixtures/e2e/stdlib/xml.ms
	"$(RELEASE_MS)" build src/ms/diagram_cmd.ms -o target/c-tool/diagram_cmd
	sh src/ms/diagram-cmd-diff.sh "$(RELEASE_MS)" target/c-tool/diagram_cmd target/release/ms-tooling-dev target/c-tool/diagram-cmd-work tests/conformance/fixtures/e2e/accept/close-error-precedence.ms tests/conformance/fixtures/e2e/stdlib/log.ms tests/conformance/fixtures/e2e/stdlib/xml.ms
	"$(RELEASE_MS)" build src/ms/inspect.ms -o target/c-tool/inspect
	sh src/ms/inspect-diff.sh "$(RELEASE_MS)" target/c-tool/inspect target/c-tool/inspect-work tests/conformance/fixtures/e2e/accept/close-error-precedence.ms tests/conformance/fixtures/e2e/stdlib/log.ms tests/conformance/fixtures/e2e/stdlib/xml.ms
	"$(RELEASE_MS)" build src/ms/facts_diff.ms -o target/c-tool/facts_diff
	sh src/compiler/tests/facts-diff.sh $(C_TOOL)/ms_check_dump target/release/ms-tooling-dev target/c-tool/facts_diff target/c-tool/facts-work $$(git ls-files 'tests/conformance/fixtures/e2e/accept/*.ms' | awk 'NR%8==0')
	sh src/compiler/tests/nodes-diff.sh $(C_TOOL)/ms_check_dump target/release/ms-tooling-dev target/c-tool/nodes-work $$(git ls-files 'tests/conformance/fixtures/e2e/accept/*.ms' | awk 'NR%8==0')
	"$(RELEASE_MS)" run src/ms/lint_diff.ms --link target/c-tool/libmstool.a -- "$(RELEASE_MS)" target/c-tool/work 3 $$(git ls-files 'tests/conformance/fixtures/e2e/accept/*.ms' 'examples/*.ms' 'src/stdlib/*.ms' | awk 'NR%4==0')

# The C driver: stage table and parse entry point, then the thin `ms` in front of a stand-in for the Rust `ms` (no Rust build needed).
c-driver-test:
	sh src/compiler/tests/driver-test.sh
