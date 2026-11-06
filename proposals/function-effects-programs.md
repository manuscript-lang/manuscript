# Function effects: hypothesis programs

Desk-checked against the rules in [function-effects.md](function-effects.md) at `HEAD` ec9d9027, then run as probes through `ms lint`; the lint fixtures in `crates/ms-tooling/tests/lint_effects/` cover P1, P4, P5, P6, P11 and the directive rules. Each program states the expected verdict and whether the rule is sound. "Pure" means no ambient authority: the function cannot obtain an effect it was not handed as a value.

## P1 Print in a helper (the basic catch)

```manuscript
fn total(items: List[Item]) Decimal:
    print(items.length())                 // error: reaches console.write: total -> print -> msrt_io_write_stdout
    return items.map(fn(i): i.price).sum()
```
Verdict: error. Sound.

## P2 CLI: config, files, network, one header per layer

```manuscript
// src/main.ms
fn main() Unit!:                          // permitted everything
    let cfg = try load("app.toml")
    try sync(cfg, host_tree(cfg.root))

// src/config.ms
// ms: effect fs.read
fn load(path: String) Config!: ...        // reaches fs.read: ok

// src/sync.ms
// ms: effect net.write
fn sync(cfg: Config, tree: FileTree) Unit!:
    for entry in try walk(tree): try upload(cfg.url, try tree.read(entry.path, none))
```
Verdict: ok. `tree.read` charges nothing (interface value); `host_tree` charged `fs.read` in `main`. `sync` cannot call `read_file` directly. Sound.

## P3 HTTP server: handlers are closures created in `main`

```manuscript
type Router:
    handle: fn(Request) Response!

fn serve(r: Router, req: Request) Response!:   // no directive
    return r.handle(req)                        // charges nothing

fn main() Unit!:
    let r = Router(handle: fn(req): save(req))  // closure body charged here: db.write ok in main
    ...
```
Verdict: ok; `serve` is pure in the ambient sense. Runtime I/O happens inside `serve`, so hover must say `effects: none (ambient)`; a reviewer looks at parameter types for capabilities. Sound as a capability model; the reading rule has to be taught.

## P4 Store interface: swap the database for memory

```manuscript
interface Store:
    fn save(o: Order) Unit!

impl Store for DbStore:
    fn save(o: Order) Unit!: return db_exec(sql(o))   // reaches db.write

fn checkout(s: Store, o: Order) Unit!:   // pure
    return s.save(o)

fn main() Unit!:
    try checkout(DbStore(url), order)    // DbStore -> Store conversion charges db.write here
```
Verdict: ok in `main`; `checkout(DbStore(url), o)` inside a pure function is an error at the conversion. Sound. Interfaces never carry tags.

## P5 Generic static dispatch

```manuscript
fn run[T: Store](s: T, o: Order) Unit!:
    return s.save(o)                     // direct call on the instance

fn pure_caller(o: Order) Unit!:
    return run(DbStore(url), o)          // error: run[DbStore] reaches db.write
```
Verdict: error, charged per instance. Sound; requires instance-level effect sets (today `p.effects` is per callable id: new work).

## P6 Higher-order stdlib calls

```manuscript
fn names(xs: List[Item]) List[String]:
    xs.each(print)                       // error: named function as a value charges console.write
    return xs.map(fn(x): x.name.clone())  // ok
```
Verdict: error on line 2, ok on line 3. Needs the value-reference rule (unverified in the checker).

## P7 Task created in `main`, waited elsewhere

```manuscript
fn finish(p: Promise[Bytes]) Int!:        // pure
    return (try p.wait()).length()

fn main() Unit!:
    let p = read_file("a.bin")           // fs.read charged here
    print(try finish(p))
```
Verdict: ok. `wait` charges nothing. Sound (authority was obtained in `main`).

## P8 Constant and default argument

```manuscript
let HOME = home_directory()              // evaluated per use

fn report(when: Timestamp = now()) String:   // default evaluated at the call site
    return HOME + when.to_string()       // error: HOME use reaches env.read

fn caller() String:
    return report()                      // error: default reaches clock.read, charged to caller
```
Verdict: both errors. Defaults must charge the caller, or a pure caller could hide a clock read behind a default. Rule added.

## P9 Logging in every layer (the friction case)

```manuscript
fn price(item: Item) Decimal:
    info("pricing {item.id}")            // error: log.ms reaches console.write
```
Verdict: error, and every layer logs. Answer: `Logger` is an interface value made in `main` and passed down, so `price(log: Logger, item)` stays pure. Cost: a parameter per layer. Stage 0 counts how many functions log; if most do, the stdlib ships `Logger` first.

## P10 Rooted tree in user code, no extra directive

```manuscript
// src/rooted.ms
// ms: effect fs.read
type RootedFs: root: String
impl FileTree for RootedFs:
    fn read(path: String, max_bytes: Int?) Bytes!:
        return read_file(child_path(self.root, try clean(path)), max_bytes).wait()
    fn children(...) ...

// src/report.ms
fn report(tree: FileTree) Text!:         // pure
    return try tree.read("a.txt", none)  // ok; read_file(...) here is an error
```
Verdict: ok. The chokepoint is the interface plus implicit deny; `contain_effect` is not needed. Residual: a symlink race remains in user code; sound confinement is a runtime primitive.

## P11 Mutual recursion and a cycle through a closure

```manuscript
fn a(n: Int) Int: return if n == 0: 0 else: b(n - 1)
fn b(n: Int) Int:
    print(n)                             // console.write reaches a and b
    return a(n)
```
Verdict: both error at `print`; the fixed point terminates. Sound.

## P12 User impl of a built-in interface called implicitly

```manuscript
impl Equal for Key:
    fn equals(other: Key) Bool:
        print("cmp")                     // console.write
        return self.id == other.id

fn lookup(m: Map[Key, Int], k: Key) Int?:
    return m.get(k)                      // implicit call to Key.equals: charged console.write
```
Verdict: error. Rule added: implicit dispatch on a concrete type (`Equal`, `Hashable`, `to_string`) is a direct call.

## P13 Sandboxed plugin

```manuscript
// ms: effect fs.read
fn run_plugin(input: Bytes) Bytes!: ...  // net.*, fs.write, process.* are errors
```
Verdict: ok; a stdlib effect added later is denied until listed. Sound.

## P14 Tests and fixtures

```manuscript
fixture tmp: return try temporary_directory()   // permitted everything, like test
test "writes": try write_file(tmp.path, "x").wait()
fn helper() Unit!: return try write_file("x", "y").wait()   // error unless its file permits fs.write
```
Verdict: as stated. `fixture` is added to rule 5.

## Findings

- Sound as an ambient-authority model; not sound as "no I/O at runtime inside this function". Hover and docs must say so.
- Rules added by the programs: defaults charge the caller (P8); implicit dispatch on concrete types is a direct call (P12); `fixture` is an entry point (P14); effect sets are per generic instance (P5).
- `contain_effect` is unnecessary: an interface value is the chokepoint (P10, P4). Interfaces carry no tags.
- The cost of implicit deny is capability threading: loggers, clocks, stores (P9). Stage 0 measures it.
