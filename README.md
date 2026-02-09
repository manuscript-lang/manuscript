# Manuscript

**Manuscript** is a programming language for **LLM-generated code**: it is designed so that generated programs are easy to review, safe by construction, and aligned with the npm ecosystem.

---

## What is Manuscript?

- **A small, statically typed language** — Indent-scoped syntax, no semicolons or braces. Compiles to JavaScript so you can use npm and existing tooling.
- **Capability-based** — Side effects (filesystem, network, shell) are declared in function signatures. Code can only do what its signature allows; reviewers see capabilities at a glance.
- **Single source of truth** — One type definition is the static type, the runtime shape, and the schema for LLM tool definitions. No separate schema files that drift.
- **Built for the LLM workflow** — Narrow surface area for reliable generation; signatures that make review possible without reading every line; deny-by-default imports and no escape hatches (`eval`, prototype tricks, etc.).

---

## Benefits

| Benefit | What it means |
|--------|----------------|
| **Auditability** | Reviewers can verify what code does from signatures and `using` clauses alone — no need to read every body and transitive import. |
| **Sandboxing** | Generated code can only use capabilities you grant (e.g. a specific `Filesystem` or `Shell`). No hidden imports or ambient authority. |
| **Small surface area** | Fewer valid ways to express things → more reliable LLM output and faster human review. |
| **No schema/type drift** | One definition updates types, runtime, and LLM-facing schemas together. |
| **Sync syntax, async runtime** | No `async`/`await` or function coloring. You write straight-line code; the runtime handles concurrency. |

---

## Why Manuscript?

TypeScript and Python weren’t designed for LLM-generated code at scale. Manuscript takes off the warts: shrink the language, make capabilities explicit, align types with schemas and runtime — so generated code is easier to review and reason about, without the usual escape hatches and hidden authority.

---

## What makes Manuscript different

### 1. Capabilities are in the signature

Side effects require explicit `using` declarations. Callers pass capabilities with `with`; no DI framework.

```manuscript
fn read_file(path: string): string using (fs: Filesystem)
  fs.read(path)

fn deploy(code: string) using (fs: Filesystem, sh: Shell)
  fs.write("app.js", code)
  sh.exec("restart")

with let fs = Filesystem(), let sh = Shell()
  deploy(code)
```

### 2. One definition = type + schema + runtime

A type is the static type, the constructor, and the schema an LLM sees. Add a field once; compiler, runtime, and tool definitions stay in sync.

```manuscript
type User
  id: number
  name: string
  email?: string
```

### 3. No escape hatches

Compiles to JS but access is controlled: no `eval`, no `Function` constructor, no prototype access. Imports are deny-by-default via `ms.toml`. Maps use null prototypes so `__proto__` is just a key.

### 4. Sync syntax, async runtime

No `async`/`await`. Explicit parallelism with `spawn` and `race`:

```manuscript
let a = spawn fetch_users()
let b = spawn fetch_orders()
let users = race([a])
let orders = race([b])
```

### 5. Small, regular syntax

Keyword, signature, indented body — same shape everywhere. Few constructs, used consistently.

```manuscript
fn greet(u: User): string
  "Hello, {u.name}"

type Point
  x: number
  y: number

test "greeting works"
  let u = User(id: 1, name: "Alice")
  assert greet(u) == "Hello, Alice"
```

### 6. Composition over inheritance

No classes or `extends`. Types compose via embedding; methods are promoted one level. Interfaces are structural (e.g. any type with `serialize(): string` satisfies `Serializable`).

```manuscript
type Animal
  name: string
  fn speak(): string
    "{name} says hello"

type Dog
  Animal
  breed: string
```

### 7. Simple generics

Type parameters only — no variance, conditional types, or type-level programming.

```manuscript
fn first[T](items: list[T]): T?
  if len(items) > 0
    items[0]
  else
    null

type Pair[A, B]
  first: A
  second: B
```

### 8. First-class testing

Tests are language syntax. Same capability system; no separate test runner config.

```manuscript
test "deploy writes and restarts"
  with let fs = MockFilesystem(), let sh = MockShell()
    deploy("console.log('hi')")
    assert fs.exists("app.js")
    assert sh.last_command() == "restart"
```

Run all tests: `manuscript test app.ms`

### 9. String templates as code

Multi-line templates with `{interpolation}`, `{if}`, `{for}` — same language and type-checking, no separate template engine.

```manuscript
fn system_prompt(user: User, tools: list[Tool]): string
  """
  You are an assistant for {user.name}.
  Available tools:
  {for tool in tools}
    - {tool.name}: {tool.description}
  {end}
  """
```

---

## More syntax

```manuscript
// Pipe, destructuring, named params
users | filter((u) => u.active) | map((u) => u.name) | join(", ")
let {name, age} = user
greet(second: "Bar", first: "Foo")

// Optionals, pattern matching
fn safe_div(a: number, b: number): number?
  if b == 0
    null
  else
    a / b

match response
  {status: 200, body} => parse(body)
  {status: 404} => null
  _ => throw Error("unexpected")

// Generators, private fields
fn count(n: number): Stream[number]
  for i in 0..n
    yield i

type Account
  _balance: number
  fn deposit(amount: number): number
    _balance += amount
```

---

## Quick start

```bash
# Install (when published)
bun add -g manuscript

# From this repo
bun run ms -- run app.ms

manuscript run app.ms      # run
manuscript check app.ms    # type-check only
manuscript test app.ms    # run test blocks
```

**VS Code:** `cd vscode-extension && ./install.sh`

---

## Who this is for

**You’re shipping or reviewing code that LLMs help write.** Manuscript is for people who want less friction in that loop.

- **AI agent and tool builders** — You expose tools to an LLM and need schemas that stay in sync with real code. In Manuscript, the type *is* the schema: one definition, type-checked by the compiler and usable as the tool spec. No separate OpenAPI or JSON Schema that drifts.
- **Reviewers of AI-generated code** — You need to trust what a patch does without reading every line and every import. Manuscript’s capability signatures (`using (fs: Filesystem)`) tell you exactly what a function can do; deny-by-default imports mean there are no surprise dependencies. Review the signatures, then skim the rest.
- **Platform and pipeline teams** — You run or orchestrate LLM-generated code and need guardrails. Manuscript gives you a small, predictable language: no `eval`, no prototype tricks, imports gated by config. You decide what each module or directory is allowed to use; the language enforces it.
- **Anyone tired of the warts** — You’ve seen generated code that’s async soup, or types that don’t match the API, or “how did this even get network access?” Manuscript is an attempt to take those warts off: one language where the syntax, types, and capabilities line up so that generated code is easier to read, review, and constrain.

---

[Syntax reference](./syntax.md) · [Standard library](./stdlib.md) · [Design](./REQUIREMENTS.md) · MIT
