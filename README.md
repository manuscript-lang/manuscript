# Manuscript

A programming language designed for LLM code generation, human review, and static verification.

---

## Why another language?

TypeScript and Python are excellent languages — expressive, battle-tested, backed by massive ecosystems. But they were designed for humans writing code by hand. When LLMs generate code at scale, different properties matter:

- **Auditability.** Can a reviewer verify what generated code does from its signature alone — without reading the body and every transitive import?
- **Sandboxing.** Can you constrain what generated code is *able* to do — not just what you *asked* it to do?
- **Surface area.** The fewer valid ways to express something, the more reliably an LLM generates correct code — and the faster a human reviews it.
- **Consistency.** If schemas, types, and runtime behavior are defined once, they can't drift apart.

These aren't weaknesses of TypeScript or Python. They're properties neither language was designed to optimize for, because the use case didn't exist when they were created.

## The thesis

Shrink the language. Make capabilities explicit. Align the type system, the syntax, and the runtime so that **if it compiles, it's safe** — and if it's safe, a human can verify it by reading signatures alone.

That's Manuscript.

---

## What makes Manuscript different

### 1. Capabilities are in the signature

In most languages, any function can import and use any module — the signature doesn't tell you. In Manuscript, side effects require explicit `using` declarations:

```manuscript
fn read_file(path: string): string using (fs: Filesystem)
  fs.read(path)

fn deploy(code: string) using (fs: Filesystem, sh: Shell)
  fs.write("app.js", code)
  sh.exec("restart")
```

A reviewer reads the signature and knows exactly what `deploy` can touch. An LLM can't accidentally generate code that reaches the network when only filesystem access was granted — there's no `import net` to reach for. Callers provide capabilities with `with`:

```manuscript
with let fs = Filesystem(), let sh = Shell()
  deploy(code)                              // production

with let fs = MockFilesystem(), let sh = MockShell()
  deploy(code)                              // test — same code, no mocks library
```

No dependency injection framework. No inversion of control containers. The language does it.

### 2. One definition = type + schema + runtime

A Manuscript type is simultaneously the static type, the constructor, and the schema an LLM sees as a tool definition:

```manuscript
type User
  id: number
  name: string
  email?: string
```

That's it. One definition — not a schema in one file and a type in another. Add a field and the compiler, the runtime, and any LLM tool definition all update together. They can't drift.

### 3. No escape hatches

Manuscript compiles to JavaScript — you get the entire npm ecosystem — but access is controlled. There's no `eval`, no `Function` constructor, no prototype access, no globals beyond a fixed set of builtins. Imports are deny-by-default: new code gets no imports until `ms.toml` explicitly allows them per directory or module. Need `lodash` in your utils? Allow it in `ms.toml`. But LLM-generated agent code in `agents/` gets only what you grant it — not the kitchen sink. Maps use null prototypes — `__proto__` is just a key, not an attack vector. Generated code runs in a way that cannot do things it wasn't given permission to do.

### 4. Sync syntax, async runtime

No function coloring. No `async`/`await`. The model writes straight-line code; the runtime handles I/O concurrency automatically. When you need explicit parallelism:

```manuscript
let a = spawn fetch_users()
let b = spawn fetch_orders()
let users = race([a])
let orders = race([b])
```

An LLM doesn't need to reason about colored functions. A reviewer doesn't need to trace async boundaries.

### 5. Small, regular syntax

Indent-scoped. No semicolons, no braces. Every construct follows the same shape — keyword, signature, indented body:

```manuscript
fn greet(u: User): string
  "Hello, {u.name}"

type Point
  x: number
  y: number

test "greeting works"
  let u = User(id: 1, name: "Alice")
  assert greet(u) == "Hello, Alice"

match status
  200..299 => "ok"
  404 => "not found"
  _ => "error"
```

A few constructs, used consistently. LLMs generate it reliably because there's less to get wrong. Humans review it quickly because there's less to read.

### 6. Composition over inheritance

No classes. No `extends`. No deep inheritance chains for an LLM to trace through. Types compose through embedding — fields and methods are promoted one level, never deeper:

```manuscript
type Animal
  name: string
  fn speak(): string
    "{name} says hello"

type Dog
  Animal
  breed: string

interface Serializable
  fn serialize(): string
```

`Dog` gets `name` and `speak()` promoted from `Animal`. Any type with a `serialize()` method satisfies `Serializable` — no `implements` keyword. An LLM reads `Dog` and sees everything it has. No method resolution order, no virtual dispatch, no scanning five parent classes to find where a method lives.

### 7. Simple generics

Generics exist but are deliberately minimal. Just type parameters:

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

No variance annotations, no conditional types, no type-level programming. Manuscript's generics do what generics should: parameterize types. Nothing more.

### 8. First-class testing

Tests are language syntax, not a library. LLMs generate code and tests in the same file, same language, with the same capability system:

```manuscript
test "deploy writes and restarts"
  with let fs = MockFilesystem(), let sh = MockShell()
    deploy("console.log('hi')")
    assert fs.exists("app.js")
    assert sh.last_command() == "restart"
```

No test runner config. No assertion library import. `manuscript test app.ms` runs every `test` block.

### 9. String templates as code

Multi-line templates with `{interpolation}`, `{if}`, and `{for}` — useful for prompt construction:

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

Same language, same types, same compiler checks. No template engine.

---

## Everything else

```manuscript
// Pipe operator
users | filter((u) => u.active) | map((u) => u.name) | join(", ")

// Destructuring
let {name, age} = user
let [first, ...rest] = items

// Named parameters
greet(second: "Bar", first: "Foo")

// Generators
fn count(n: number): Stream[number]
  for i in 0..n
    yield i

// Optionals with narrowing
fn safe_div(a: number, b: number): number?
  if b == 0
    null
  else
    a / b

// Pattern matching
match response
  {status: 200, body} => parse(body)
  {status: 404} => null
  _ => throw Error("unexpected")

// Private fields — enforced by compiler
type Account
  _balance: number
  fn deposit(amount: number): number
    _balance += amount
```

---

## Quick start

```bash
bun add -g manuscript
manuscript run app.ms
manuscript check app.ms        # type check without running
manuscript test app.ms         # run test blocks
```

**VS Code extension:** `cd vscode-extension && ./install.sh`

---

## Who this is for

- **AI agent builders** who want tool definitions that are also type-checked code
- **Teams reviewing AI-generated code** who need to verify safety from signatures, not source reading
- **Anyone building LLM pipelines** where generated code must be sandboxed and capability-controlled

---

[Syntax reference](./syntax.md) · [Standard library](./stdlib.md) · [Design document](./REQUIREMENTS.md) · MIT
