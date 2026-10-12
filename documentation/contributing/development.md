+++
title = "Development, checks, and publishing"
weight = 2
+++

# Development workflow

Run commands from the repository root. Make downloads and verifies the SDK pinned by `.go-version` and `scripts/toolchains.sha256`, then sets `MANUSCRIPT_GO` and `PATH` consistently. Initial setup needs Make, curl, tar, a SHA-256 utility, and Internet access. Native application builds are offline after setup.

```sh
make build
make coverage
make race
make check
make fuzz
make book-check
make dist-check
```

`make coverage` runs the entire unit and native conformance suite. It writes a statement profile and an HTML report in `.artifacts/coverage/`; CI uploads both. Subprocess-built executables are validated by observable end-to-end expectations, but their execution does not increase Go package coverage. Read percentages alongside accepted/rejected source cases and runtime tests.

`make fuzz` exercises strict parsing, editor recovery, and compilation for ten seconds each; use `FUZZTIME=1m` for a longer local run. Go retains reproducible failures as fuzz corpus inputs. Add a named regression and fix the source behavior before declaring a failure resolved.

Use `make docs` for generated API sources, `make book` to rebuild committed HTML, and `make book-check` for strict link, highlighting, and publication checks in a temporary directory. Set `HUGO=/path/to/hugo` if Hugo is not on PATH. Hugo Extended 0.146.7 matches CI. Node is required for book and extension checks; a C compiler is required for Go race tests. Delve is required for native debugger integration.

Tests that open HTTP/socket listeners need local loopback access. In a workspace with a read-only home directory, choose writable `GOCACHE` and `GOPATH` paths, for example `/tmp/manuscript-go-cache` and `/tmp/manuscript-go`. These environment requirements are separate from compiler correctness.

## Conformance and distributions

Make prepares and selects the bundled toolchain for the end-to-end suite. It builds accepted modules, executes their `test` blocks, verifies rejected variants, exercises CLI commands, and checks evaluation order, cleanup, numeric faults, and signal cancellation. Race checks additionally require a C compiler. CI runs formatting checks, vet, the complete suite, race tests, and `make dist-check`, which exercises a copied single binary with no Go on `PATH`, empty caches, and package downloads disabled.

`make dist` creates a self-contained archive in `dist/`.
`sh scripts/package.sh <os> <arch>` packages `linux`, `darwin`, or `windows` for
`amd64` or `arm64`. Distributions contain the binary, examples, and license notices.
Update `.go-version` and `scripts/toolchains.sha256` together when upgrading Go.

## Preview and publish the book

Start with [the introduction](../learn/_index.md), [the language tour](../learn/tour.md), and [the complete module reference](../standard-library/reference/_index.md).

Read the published book at <https://manuscript-lang.github.io/manuscript/>. Changes to `documentation/` publish automatically after CI passes on `main`.

Author guides in `documentation/`; site configuration and assets live in `website/`. The Markdown guides are rendered directly with [Hugo](https://gohugo.io/) and the [Hugo Book theme](https://github.com/alex-shpak/hugo-book). Install Hugo Extended 0.146 or newer.

```sh
hugo --source website server --bind 127.0.0.1 --port 4000 --renderToMemory
```

Open <http://localhost:4000> to browse the chapters, search the book, and follow links between concepts. The preview listens only on your computer and reloads when you edit the guides. Mermaid diagrams use the theme's bundled local runtime.

```sh
hugo --source website --minify
```

The static site is generated in the repository root’s `docs/`, which is committed for GitHub Pages to serve. Edit the Markdown guides in `documentation/`, then rebuild; files in `docs/` are generated output. Chapter indexes use `_index.md`; each page's front matter sets its title and reading-order weight. New Markdown pages appear automatically. Site settings live in `website/hugo.toml`. The `website/static/.nojekyll` marker is copied into `docs/` so Pages serves the Hugo output directly.

The root `.msversion` file contains the current documentation version (initially
`0.1.0`, without a `v` prefix). Hugo reads it for the header's version dropdown,
homepage badge, sidebar, and footer. Change this file and rebuild to update all
documentation version labels.

When older documentation is available, add its version and published site URL to
`website/data/docs_versions.toml` as an `[[archives]]` entry. Relative URLs such as
`versions/v0.1.0/` respect the site's configured base URL; full URLs can point to a
separate docs host. Selecting an archive opens that version's documentation home,
so pages added in newer versions do not produce broken links. The current version
is always included automatically. Archive entries only link to published sites;
they do not create or preserve snapshots. Keep snapshots outside the generated
`docs/` directory, which production builds clean before publishing.

Hugo Book v13 is vendored in `website/themes/hugo-book/`, including its MIT license. The exact upstream revision is recorded in `website/themes/hugo-book/UPSTREAM`.

The documentation's visual design lives in `website/assets/_custom.scss`, with layout and
navigation overrides in `website/layouts/`. The overview uses the `docs-home` shortcode;
`website/assets/docs.js` provides theme preferences, copy buttons, and mobile keyboard
controls. Keep site customizations in these files rather than editing the
vendored theme. After a presentation change, rebuild `docs/` with `hugo --source website --minify
--panicOnWarning --cleanDestinationDir`.

Label Manuscript code fences `manuscript`; keep terminal output labeled `text`.
The docs reuse the VS Code extension's grammar in
`extensions/vscode/syntaxes/manuscript.tmLanguage.json`. Change lexical rules
there, then run `node --test tests/docs/highlighting.test.cjs` to check the
browser adapter before rebuilding the site.

## Continuous integration and releases

[The GitHub Actions pipeline](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/cicd.yml) builds the design book on branch pushes and pull requests using Hugo Extended 0.146.7. Pushes that only change generated `docs/` files are skipped. Warnings and broken Markdown page links fail the build. The theme is vendored, so no submodule setup is needed.

The pipeline also calls [the language checks](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/test-language.yml) with Go 1.25.1: formatting, vet, statement coverage, unit and native end-to-end tests, parser/compiler fuzz smoke checks, race checks, and a CLI build and example run. Deployment requires both the book build and language checks to pass. The language workflow can also be run independently from the Actions tab.

The [distribution workflow](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/release.yml) builds archives for all
six targets and tests their standalone commands on the native OS and architecture.
Manual runs produce Actions artifacts; `v*` tags publish verified archives and
checksums to GitHub Releases.

After validation succeeds on the repository's default branch (`main`), the pipeline builds with the GitHub Pages URL, commits the generated `docs/` files to that branch, and explicitly requests a Pages build. This request is needed because pushes made with `GITHUB_TOKEN` do not trigger Pages builds automatically. Pull requests and other branches only run validation. You can also run the pipeline manually from the Actions tab; publishing still requires the default branch. Outdated runs skip publishing, and a concurrent branch update causes the push to fail rather than overwrite newer work.

Keep **Settings → Pages → Source** set to **Deploy from a branch**, with **main** and **/docs** selected. The workflow uses the built-in `GITHUB_TOKEN` with contents and Pages write permissions; no deployment secrets are required. Repository rules must allow the workflow to push generated documentation to `main`. If branch protection blocks that push, regenerate and merge `docs/` through a pull request instead. For a custom domain, configure it in Pages settings and update `baseURL` in `website/hugo.toml` before rebuilding the committed output; CI uses the URL reported by Pages.

For branch protection, require the **Build design book** and **Language checks / test** status checks. To reproduce the book validation locally with Hugo Extended 0.146.7:

```sh
hugo --source website --minify --panicOnWarning --destination /tmp/manuscript-book-validation --baseURL "https://example.org/manuscript/"
```

## Generate the standard library reference

Run `make docs` from the repository root after changing standard definitions.
`make docs-check` verifies that checked-in outputs match; the Pages workflow runs
this check before validation and deployment.

`scripts/docgen` reads the checker’s standard registry loaded from the bundled
`stdlib/*.ms` declarations, including intrinsic receiver operations. The shipped
binary needs no source checkout.
It captures checked signatures, generic bounds, fields, cases, and operations
without maintaining a second API catalog. The intrinsic prelude is included.
Special contextual calls and constructors are documented in
[call rules](https://github.com/manuscript-lang/manuscript/blob/main/tooling/docgen/call-rules.md), which require review when
`checker/calls.go` changes.

Generated module pages live in `documentation/standard-library/reference/`. Hugo copies
`website/static/stdlib.md`, `website/static/stdlib.json` (schema version 1), and `website/static/llms.txt`
to the Pages site root. Relative links support repository Pages prefixes and
custom domains. `stdlib.md` contains the entire implemented API in one plain-text
document for LLM ingestion; the JSON has stable sorted modules and declarations.
The existing design chapters explain behavior and identify proposed extensions.
