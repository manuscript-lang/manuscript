HUGO ?= hugo
VSCODE_CLI ?= code
# The ms that runs the repository tools in tools/ (`make build` produces it).
MS ?= $(CURDIR)/.artifacts/build/ci/src/cli/ms-c
BENCHREPEATS ?= 5
BENCHFILTER ?=
BOOK_CHECK_DIR ?= /tmp/manuscript-book-validation

# Each of these runs tools/<name>.ms with the built ms; the tool's header comment says what it checks.
TOOLS := doctor view-matrix scaling-check leak-check cancel-sweep perf-counts resource-matrix close-matrix copy-check removed-check

.PHONY: build conform verify verify-full repo-check licenses licenses-check docs docs-check docs-coverage book book-check dist dist-check bench-check stdlib-bench poison-check ownership-fuzz count-check vscode-package vscode-install $(TOOLS)

# Configures and builds the `ci` preset (src/README.md); `ms-c` lands in $(MS).
build:
	cmake --preset ci
	cmake --build --preset ci

# The conformance corpus replayed with the ms just built (tools/conform-run.ms).
conform: build
	cmake --build --preset ci --target conform

# Routine feedback; the merge gate adds the conformance corpus, removed spellings, the book and the package.
verify: repo-check bench-check docs-check licenses-check

verify-full: verify conform removed-check book-check dist-check

$(TOOLS): build
	HUGO="$(HUGO)" $(MS) run tools/$@.ms

# The corpus with every dead statement slot poisoned (MS_POISON_SLOTS=1), under the default backend and Cranelift.
poison-check: build
	MS_POISON_SLOTS=1 $(MS) run tools/conform.ms
	CONFORM_FAST=1 MS_BACKEND=cranelift MS_POISON_SLOTS=1 $(MS) run tools/conform.ms

# Random ownership programs; SEED and COUNT pick the run. Nightly on main.
ownership-fuzz: build
	$(MS) run tools/ownership-fuzz.ms -- $(or $(SEED),1) $(or $(COUNT),300)

count-check: build
	$(MS) run tools/count-check.ms
	MS=$(MS) $(MS) run tools/count-check-selftest.ms

dist: build
	$(MS) run tools/package.ms

# Extracts the archive for this host and runs the packaged binary on the hello example.
dist-check: dist
	$(MS) run tools/dist-check.ms

# Use the locked editor dependencies; packaging runs the extension checks and bundle.
vscode-package:
	cd extensions/vscode && npm ci && npm run package

vscode-install: vscode-package
	@command -v "$(VSCODE_CLI)" >/dev/null 2>&1 || { echo 'VS Code CLI not found; add code to PATH or set VSCODE_CLI=/path/to/code.' >&2; exit 1; }
	@vsix=$$(node -p 'const p = require("./extensions/vscode/package.json"); "extensions/vscode/" + p.name + "-" + p.version + ".vsix"') && \
		"$(VSCODE_CLI)" --install-extension "$$vsix" --force

# Rust tools kept until they are ported to Manuscript (#6380): repo-check, licenses, docs.
# Nested matches, .ms formatting, stdlib syntax, release pins, workflow triggers, Rust unsafe allow-list.
repo-check:
	cargo run --release --locked -q -p ms-repo-check

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

bench-check: build
	@for t in $$(find bench/perf -name ms.toml | sort); do \
		(cd $$(dirname $$t) && "$(MS)" check ms.toml) || exit 1; \
	done
	@for f in $$(find bench/perf -name '*.ms' -not -path 'bench/perf/formatter-flow/*' -not -path 'bench/perf/results/*' | sort); do \
		p=$$(dirname $$f); \
		while [ $$p != bench/perf ] && [ ! -f $$p/ms.toml ]; do p=$$(dirname $$p); done; \
		[ -f $$p/ms.toml ] || "$(MS)" check $$f || exit 1; \
	done
	@for t in bench/tools/*.ms bench/agent/*.ms; do "$(MS)" check $$t || exit 1; done
	@for t in bench/tools/*_test.ms; do "$(MS)" test $$t || exit 1; done

# Runs the bench blocks of bench/perf/stdlib; BENCHREPEATS is the sample count per case.
stdlib-bench: build
	MS="$(MS)" "$(MS)" run bench/tools/stdlib_bench.ms -- $(BENCHREPEATS) $(BENCHFILTER)
