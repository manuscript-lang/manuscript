# Module Loading: Stdlib as Normal Modules with Per-Program Runtime

## Context

Stdlib modules (`std/math`, `std/collections`, etc.) are currently treated as special: their exports are compiled into `__ms_runtime` via `compileAll()`, and codegen emits `const { abs } = __ms_runtime;` for stdlib imports. This creates a separate loading mechanism from user modules, which breaks in compiled binary mode and is unnecessarily complex.

**The fix:** Stdlib modules should flow through the exact same compilation pipeline as user modules — parse, typecheck, codegen, emit JS. The only difference is source resolution: stdlib sources come from `src/stdlib/` (dev) or `Bun.embeddedFiles` (binary) instead of the user's `src/` directory. Codegen emits normal `import`/`require` for them, just like local modules.

## Problems Being Fixed

1. **Stdlib has separate compilation machinery** — `compileAll()` bundles all stdlib into `__ms_runtime`, completely different from how user modules are compiled
2. **Codegen special-cases stdlib** — `genImport` emits `const { abs } = __ms_runtime;` for stdlib instead of a normal import
3. **Sync loading breaks in binary** — `getStdlibSourceSync()` can't read `Blob.text()` synchronously
4. **Global mutable runtime** — `__ms_runtime` is a shared singleton
5. **Dead code** — `ensureStdlibCache()`, `getAllStdlibSources()` in loader; `runtime.bundle.js`

## Design

### Stdlib joins the module graph

Currently, `buildModuleGraph()` in `resolver.ts` already detects stdlib imports and calls `getStdlibSource()` to warm the cache, but doesn't add them to the graph. The change: **include stdlib modules in the module graph** just like local modules.

When `resolveSpecifier()` returns `{ kind: "stdlib", module: "math" }`:
- Resolve the source via `getStdlibSource("math")` (async, works in both dev and binary)
- Add it to the module graph with a virtual path (e.g., `stdlib://math.ms`)
- Parse, typecheck, and codegen it the same as any local module
- Codegen emits a normal `import`/`require` statement pointing to the emitted JS file

### Runtime no longer contains stdlib

`__ms_runtime` (or `createRuntime()`) only contains:
- Extern functions (JS API implementations: `print`, `len`, `sqrt`, etc.)
- Builtins compiled from `builtins.ms` (pure Manuscript functions: `ok`, `err`, `assert`, etc.)

Stdlib pure functions (`abs`, `clamp`, `first`, etc.) are no longer merged into the runtime — they're compiled to JS files and imported normally.

### Codegen change

In `genImport()` (`src/codegen/declarations.ts:23-32`), remove the stdlib special case. Stdlib imports should emit the same `import`/`require` as local imports, using the emit path from `importEmitPaths`.

**However:** Stdlib modules declare `extern fn` for functions implemented in the runtime (e.g., `extern fn sqrt(x: number): number` in `math.ms`). The codegen for extern functions in stdlib modules needs to emit `const sqrt = __ms_runtime.sqrt;` — this is already how builtins work, so the pattern exists.

### CLI execution flow

**Single-file mode** (no ms.toml):
- Currently: compile single file, execute with `new Function` and `__ms_runtime`
- If the file imports `std/math`, we need to also compile `math.ms` and make it available
- Options: (a) inline the compiled stdlib into the wrapped code, or (b) write to temp dir and use ESM imports like project mode
- Simplest: when stdlib imports are detected in single-file mode, use the same temp-dir + ESM approach that project mode uses

**Project mode** (ms.toml):
- Already writes all modules to temp dir and runs via ESM
- Just need to include stdlib modules in the module graph so they get compiled and written too

### Per-program runtime

Replace `export const __ms_runtime` with `export function createRuntime()`:
- Each program execution gets a fresh runtime
- Only builtins + extern functions, no stdlib

## Changes

### 1. `src/modules/resolver.ts`
- When `resolveSpecifier` returns stdlib, `buildModuleGraph` should add the stdlib module to the graph
- Use a virtual path convention for stdlib modules (e.g., `<stdlib>/math.ms`)
- `getStdlibSource()` provides the source content
- Import `isStdlibImport` from `../shared/constants` (not `../stdlib/loader`)

### 2. `src/codegen/declarations.ts`
- Remove the stdlib special case in `genImport()` — stdlib imports use the same `import`/`require` path as local imports
- The `importEmitPaths` map (populated by the compiler) provides the emit path

### 3. `src/cli/compiler.ts`
- In `compileProject()` / `runProjectTypecheckLoop()`, handle stdlib modules in the graph
- Compute `importEmitPaths` for stdlib → emitted JS path
- `runProjectTypecheckLoop()` → async (for `resolveStdlibImports`)

### 4. `src/cli/cli.ts`
- Single-file `runCommand`: if stdlib imports detected, upgrade to project-like compilation (temp dir + ESM)
- Or: always use project mode when imports are present (stdlib or local)
- Replace global `__ms_runtime` with `createRuntime()`
- Same for `testCommand` and `replCommand`

### 5. `src/stdlib/loader.ts`
- Delete `getStdlibSourceSync()`, `ensureStdlibCache()`, `getAllStdlibSources()`
- `getStdlibTypes(name)` → async
- `getStdlibAST(name)` → async
- `resolveStdlibImports()` → async
- `getStdlibExportLocation()` → async
- Remove `isStdlibImport` re-export

### 6. `src/builtin/compiled.ts`
- Remove stdlib compilation entirely — only compile `builtinsSource`
- Delete `getAllStdlibSources` import
- Rename `compileAll` → `compileBuiltins` (builtins only)

### 7. `src/runtime/runtime.ts`
- Replace `export const __ms_runtime` with `export function createRuntime()`
- Remove `Object.assign(__ms_runtime, getCompiledBuiltins(...))` top-level side effect
- Call `getCompiledBuiltins(runtime)` inside `createRuntime()`

### 8. `src/lsp/stdlib.ts`
- `resolveStdlibDefinition()` → async
- `getStdlibHover()` → async

### 9. `vscode-extension/src/server.ts`
- Await stdlib LSP calls

### 10. Test files
- `tests/helpers/execution.ts` — use `createRuntime()` instead of global
- `tests/runtime/runtime.test.ts` — same

### 11. Cleanup
- Delete `src/runtime/runtime.bundle.js`

## Extern fn: no changes now, extensible later

**Current behavior preserved:** `extern fn sqrt(...)` in any module emits `const sqrt = __ms_runtime.sqrt;`. Since stdlib modules now go through the normal codegen (which already has `__ms_runtime` available via ESM import or function wrapping), this just works.

**Future extensibility:** Add an optional `from` clause to extern fn syntax:
```
extern fn sqrt(n: number): number                                  // → __ms_runtime.sqrt (today)
extern fn fetch(url: string): Promise[Response] from "node:http"   // → import from JS module (future)
```
The `from`-less form keeps working. The `from` form is a pure additive syntax + codegen change. **Zero extern fn changes in this PR.**

## Open questions

1. **Single-file with stdlib import:** When a standalone file (no ms.toml) imports `std/math`, should we auto-upgrade to project-mode compilation (temp dir + ESM), or inline the compiled stdlib into the wrapped code?
2. **Virtual paths for stdlib in module graph:** What convention? `<stdlib>/math.ms` or `stdlib://math.ms`?

## Files Modified

| File | Change |
|------|--------|
| `src/modules/resolver.ts` | Add stdlib to module graph, fix imports |
| `src/codegen/declarations.ts` | Remove stdlib special case in `genImport` |
| `src/cli/compiler.ts` | Handle stdlib in project compilation, async typecheck |
| `src/cli/cli.ts` | Per-program runtime, handle stdlib in single-file mode |
| `src/stdlib/loader.ts` | Remove sync functions, make async, delete dead code |
| `src/builtin/compiled.ts` | Builtins only, remove stdlib compilation |
| `src/runtime/runtime.ts` | `createRuntime()` factory |
| `src/lsp/stdlib.ts` | Async functions |
| `vscode-extension/src/server.ts` | Await stdlib calls |
| `tests/helpers/execution.ts` | Use `createRuntime()` |
| `tests/runtime/runtime.test.ts` | Use `createRuntime()` |
| `src/runtime/runtime.bundle.js` | Delete |

## Verification
- `bun tsc` — no type errors
- `bun test` — all tests pass
- `bun run build` — binary builds
- `ms run file-with-stdlib-import.ms` works in dev and binary
- Stdlib extern functions (e.g., `sqrt` from `std/math`) resolve to runtime implementations
- Programs without stdlib imports don't trigger any stdlib compilation
