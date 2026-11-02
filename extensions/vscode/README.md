# Manuscript for VS Code

Requires VS Code 1.91 or newer.

Download the self-contained `ms` binary from [Manuscript Releases](https://github.com/manuscript-lang/manuscript/releases), place it on PATH, or configure `manuscript.serverPath`. A source checkout can build it with `make build`. No other language toolchain is required to use `ms`.

Open `.ms` files for typed lexical/member completion, named argument completion and call snippets, auto-imports, signature help, diagnostics, type hover, definition/type navigation, project references and checked rename, hierarchical/workspace symbols, semantic highlighting, folding, type hints, formatting, import organization, and lint fixes. Completion works during unfinished calls and member accesses. Source synchronization uses UTF-16 incremental edits. **Manuscript: Restart language server** reloads the compiler path.

Inline type hints are off by default to keep code readable. Hover over a name to see its type. To show inline hints, set `editor.inlayHints.enabled` to `on` or `offUnlessPressed` under `[manuscript]` in your VS Code settings.

**Manuscript: Capture sampling profile** chooses a new output directory and runs `ms profile` on the containing project or source in a terminal. The bundle contains the executable, folded stacks, a pprof profile, a top report, and a manifest. Open `profile.pb` with a pprof viewer.

Project manifests provide detected build/check/test/lint tasks with positioned problem matching. Process invocation uses argument arrays rather than a shell. Indentation defaults to four spaces and Manuscript is the default formatter for `.ms` files.

From the repository root, package and install the extension with Make and the Node version in [`.node-version`](../../.node-version) (including npm):

```sh
make vscode-install
```

The VS Code CLI (`code`) must be on PATH. On macOS, run **Shell Command: Install 'code' command in PATH** from VS Code's Command Palette. To use another CLI executable or a path containing spaces, run `make vscode-install VSCODE_CLI="/path/to/code"`. Installation uses that CLI's editor environment; run it where you want the extension installed. Repeated installs replace the same extension version.

`make vscode-package` only creates `extensions/vscode/<name>-<version>.vsix`, using the extension's current package metadata. Both targets install locked npm dependencies and reuse the package script's checks and bundling. They package the client only; the `ms` binary still needs the setup described above.

For development inside `extensions/vscode`:

```sh
npm ci
npm run check
npm run package
```

Install the generated VSIX with **Extensions: Install from VSIX**. CI checks editor tests and packages the bundled extension as an artifact. Marketplace publishing is a separate release step.

The server rechecks affected modules rather than individual syntax nodes. Rename refuses colliding names and requires a clean affected workspace.

`ms profile module-or-project --out-dir new-directory` captures the sampling profile and retains the executable for source attribution. Existing directories are rejected.
