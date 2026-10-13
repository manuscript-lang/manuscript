# Manuscript for VS Code

Download the self-contained `ms` binary from [Manuscript Releases](https://github.com/manuscript-lang/manuscript/releases), place it on PATH, or configure `manuscript.serverPath`. A source checkout can build it with `make build`, which prepares Go automatically. Native debugging uses Delve embedded in `ms`; no `dlv` installation is needed. On macOS, Xcode command line tools must supply Apple’s `debugserver`. No separate Go installation or Go extension is required to use `ms`.

Open `.ms` files for typed lexical/member completion, named argument completion and call snippets, auto-imports, signature help, diagnostics, type hover, definition/type navigation, project references and checked rename, hierarchical/workspace symbols, semantic highlighting, folding, type hints, formatting, import organization, and lint fixes. Completion works during unfinished calls and member accesses. Source synchronization uses UTF-16 incremental edits. **Manuscript: Restart language server** reloads compiler/debugger paths.

Use F5 with the generated **Debug Manuscript** configuration or **Manuscript: Debug current file**. The extension's Manuscript DAP layer compiles a debug executable, verifies its build/source metadata, and delegates native control to Delve. It displays source frame and variable names, lazy records/collections/variants/views, simple source watch expressions, and a separate execution/service inspection scope. It reads stopped-process state without invoking application operations. Project builds require a current `ms.lock`; create/update it explicitly with `ms lock path/to/ms.toml`. Running/debugging requires a trusted workspace.

**Manuscript: Capture profile or trace** selects CPU pprof, heap pprof, or execution tracing, chooses a new output file, and runs the containing project or source in a terminal. CPU labels and trace regions identify source functions; task-group/scheduled work carries task attribution. Open artifacts with `ms pprof` or `ms trace`.

Project manifests provide detected build/check/test/lint tasks with positioned problem matching. Process invocation uses argument arrays rather than a shell. Indentation defaults to four spaces and Manuscript is the default formatter for `.ms` files.

Development:

```sh
npm ci
npm run check
npm run package
# Optional live native DAP integration (requires built ms):
MANUSCRIPT_DAP_TEST=1 MANUSCRIPT_MS=/path/to/ms node tests/debug-adapter.test.js
```

Install the generated VSIX with **Extensions: Install from VSIX**. CI checks Go/native/race behavior, editor tests, live DAP behavior, and packages the bundled extension as an artifact. Marketplace publishing is a separate release step.

The server rechecks affected modules rather than individual syntax nodes. Rename refuses colliding names and requires a clean affected workspace. Runtime frames remain available as subdued native entries; complex watch expressions use Delve's native syntax.

`ms profile module-or-project -o new-directory` captures all three profiles and retains the optimized executable, build/source metadata, static inspection, and a bundle manifest for reproducible symbolization. Existing directories are rejected.

Debugger value views are read-only. Locals whose native container slot has been recycled after its final use are shown as unavailable; complex watches retain native Go syntax.
