# Manuscript for VS Code

Requires VS Code 1.91 or newer.

Download the self-contained `ms` binary from [Manuscript Releases](https://github.com/manuscript-lang/manuscript/releases), place it on PATH, or configure `manuscript.serverPath`. A source checkout can build it with `make build`, which prepares Go automatically. No separate Go installation or Go extension is required to use `ms`.

Open `.ms` files for typed lexical/member completion, named argument completion and call snippets, auto-imports, signature help, diagnostics, type hover, definition/type navigation, project references and checked rename, hierarchical/workspace symbols, semantic highlighting, folding, type hints, formatting, import organization, and lint fixes. Completion works during unfinished calls and member accesses. Source synchronization uses UTF-16 incremental edits. **Manuscript: Restart language server** reloads the compiler path.

Inline type hints are off by default to keep code readable. Hover over a name to see its type. To show inline hints, set `editor.inlayHints.enabled` to `on` or `offUnlessPressed` under `[manuscript]` in your VS Code settings.

**Manuscript: Capture profile or trace** selects CPU pprof, heap pprof, or execution tracing, chooses a new output file, and runs the containing project or source in a terminal. CPU labels and trace regions identify source functions; task-group/scheduled work carries task attribution. Open artifacts with `ms pprof` or `ms trace`.

Project manifests provide detected build/check/test/lint tasks with positioned problem matching. Process invocation uses argument arrays rather than a shell. Indentation defaults to four spaces and Manuscript is the default formatter for `.ms` files.

Development:

```sh
npm ci
npm run check
npm run package
```

Install the generated VSIX with **Extensions: Install from VSIX**. CI checks editor tests and packages the bundled extension as an artifact. Marketplace publishing is a separate release step.

The server rechecks affected modules rather than individual syntax nodes. Rename refuses colliding names and requires a clean affected workspace.

`ms profile module-or-project --out-dir new-directory` captures all three profiles and retains the optimized executable, build/source metadata, static inspection, and a bundle manifest for reproducible symbolization. Existing directories are rejected.
