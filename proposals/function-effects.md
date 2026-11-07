# Function effects

## Summary

- Problem: nothing says what a function reaches outside itself; `ms review` prints `unknown` for every native, and agents add I/O to pure helpers unnoticed.
- Change: implicit deny. A function is pure unless `// ms: allow_effect` permits what it reaches; `// ms: effect` declares one. Exported stdlib functions declare theirs with a `std.` prefix; callers inherit; the checker rejects unpermitted reach with the call path. No grammar change.
- Decision requested: approve the contract and the warning-then-error rollout with `ms check --fix`.

## Status

Implemented 2026-11-06 at `HEAD` ec9d9027: checker, MSL116 warning and stdlib tags built; the 14 programs ran as probes. Not yet built: `ms check --fix`, `ms review` rows, hover, drift rule. Direction (Chinmay): tag and enforce; user code too; fine-grained; implicit deny; `allow_effect` to permit and `effect` to declare; `std.` prefix; mark only importable functions; purity is never declared; FFI out of scope. Acceptance cases: [hypothesis programs](function-effects-programs.md).

## Contract

1. Two directives above a function, or in a file's header comment for every function in the file, one pattern or name per line.
   `// ms: allow_effect P` permits effects matching `P` (`a.b.c`, `a.b.*`, `*.write`, `*`).
   `// ms: effect NAME` declares one: the function performs `NAME`, and callers see its declared names instead of what its body reaches. Stdlib tags are declarations with the body unscanned.
2. A function's effects are the effects of tagged stdlib functions it reaches, transitively, flow-insensitive. Each must match a line in scope; no line means pure. A miss is an error at the first call that brings it in, with the path. A function's own lines can only tighten its file's.
3. `main`, `test` and `fixture` may perform everything; what they call is still checked.
4. Authority is charged where obtained, not used: writing a closure, naming a function as a value, or converting a record to an interface (union of its methods) charges the enclosing function. Calling a function value or interface method charges nothing. Interfaces carry no lines.
5. "Pure" means no ambient authority, not no I/O at run time: a pure function may use what it was handed.
6. Defaults charge the caller; constants per use; implicit dispatch on a concrete type (`Equal`, `Hashable`, `to_string`) is a direct call; effect sets are per generic instance.
7. No value tracking, no runtime effect; FFI is outside the system.

## Examples

```manuscript
fn total(items: List[Item]) Decimal:      // pure
    print(items.length())                 // error: reaches std.console.write: total -> print
    return items.map(fn(i): i.price).sum()
```

```manuscript
// ms: allow_effect std.fs.read           (reads only; as a file header it covers the file)
fn load(path: String) Config!:
    return try parse(try read_file(path).wait())
```

```manuscript
fn index(tree: FileTree) Index!:          // pure: takes the capability
    return build(try walk(tree))

fn main() Unit!:
    let idx = try index(host_tree("/data"))   // std.fs.read charged here

test "indexes":
    try expect_equal(try index(memory_tree()).size(), 3)
```

Custom effect: `effect` declares it, `allow_effect` permits what the body needs, and callers see only the declared names:

```manuscript
// ms: effect db.write                    (declared: callers see db.write)
// ms: allow_effect std.net.connect       (permitted: the body may reach it)
fn exec(sql: String) Unit!:
    return try pg_client().run(sql)

// ms: allow_effect db.*                  (domain file: may use the database, not the network)
fn save(order: Order) Unit!:
    return try exec(sql_for(order))       // ok; fetch(...) here is an error
```

Rooted tree in user code; the interface is the chokepoint:

```manuscript
// ms: allow_effect std.fs.read           (the only file that may touch fs)
impl FileTree for RootedFs:
    fn read(path: String, max_bytes: Int?) Bytes!:
        return read_file(child_path(self.root, try clean(path)), max_bytes).wait()

fn report(tree: FileTree) Text!:          // elsewhere, pure; read_file(...) here is an error
    return try tree.read("a.txt", none)
```

## Stdlib

```manuscript
// ms: effect std.fs.read
export fn read_file(path: String, max_bytes: Int? = none) Promise[Bytes]: ...
// ms: effect std.clock.read
export fn now() Timestamp: ...
// ms: effect std.console.write
export fn print(value: Printable) Unit: ...
```

- Vocabulary: `std.fs.{read,write,delete}`, `std.net.{connect,listen}`, `std.process.{run,signal,read,write}`, `std.env.{read,write}`, `std.clock.{read,sleep}`, `std.random.read`, `std.console.{read,write}`, `std.system.read`. User effects are unprefixed (`db.write`); `std.*` is reserved.
- Tags follow logical capability, not extern calls: a function lists every capability it exposes (`ulid` reads random and clock); handle methods inherit from where the handle was opened; pure computation is untagged. Wrappers (`host_tree`) inherit by inference. Externs and `stdlib/internal` are never marked. A golden listing in `crates/ms-tooling/tests/stdlib_effects.txt` makes tag changes reviewable.
- Drift: repo-check flags an exported function that reaches `stdlib/internal` with no tag on the path.
- Stdlib effect sets are API: a new tag is a breaking change in release notes, migrated by `ms check --fix`.

## Design

- Declared effects are a second set beside the memory `read`/`write`/`unknown` in `p.effects`: dense ids, bitsets, the existing worklist, sorted output. Diagnostic path: shortest, ties by name.
- Directives follow `// ms: native`; `doc.rs` skips `// ms:` lines.
- New checker work (hypotheses): value-reference charging (`scan_call` fires on calls only), conversion charging, per-instance sets, default attribution, implicit-dispatch edges, per-module summaries for incremental checking.
- `ms check --fix` writes the minimal `allow_effect` header from the inferred set; `undeclared-effect` is a warning first, then an error at a release.
- `ms review --diff`: `EFFECT+` reports new reach (`std.net.connect via save -> upload -> fetch`) and new permission or declaration (`std.net.connect permitted on save`, `db.write declared on exec`), comparing effective permission sets so moves into wider files count; permission rows rank first. Hover and `search_symbol` show `effects: std.fs.read` or `pure (ambient)` plus capability parameters by type. `ms review --effect X` filters.
- Logging is the main friction: `log.ms` reaches `std.console.write`. Answer: a `Logger` interface value passed down. Stage 0 counts it.

## Components

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check` | directive, implicit deny, rules 4 and 6, `--fix` | the 14 hypothesis programs as fixtures |
| `crates/ms-syntax` `doc.rs` | skip `// ms:` lines | hover snapshot |
| `stdlib/**/*.ms`, `ms-repo-check` | tags on exported host functions; drift rule | `ms check stdlib` clean |
| `ms-tooling`, `ms-lsp` | facts, `EFFECT+` permission rows, `--effect`, hover | `tests/review.rs`, LSP snapshot |
| `stdlib/log.ms`, repo, docs, vscode | `Logger`; migrate with `--fix`; page; highlighting | `make verify-full` |

## Alternatives

- `deny_effect` carve-outs fail open when the stdlib adds an effect under a wildcard; `contain_effect` is unneeded once interfaces carry authority; `@` syntax needs grammar, AST and formatter changes; value conditions are runtime facts and live in capability values such as rooted types.

## Stages

0. Measure on `stdlib/`, `examples/`, the largest `tests/` project: files needing a header, files needing `allow_effect *`, functions that log. Stop if most files need `effect *`.
1. Directive, inference, `std.fs` and `std.net` tags, warning, `--fix`, review rows, fixtures.
2. Remaining tags, drift rule, repo migration, hover, `--effect`, `Logger`.
3. Error at a release; docs, editor, `bench/agent` challenge. Stop if dogfood pushes people to `allow_effect *`.

## Open questions

- Warning for one release, then error? Recommend yes.
