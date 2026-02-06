# Manuscript Syntax v4.0

A minimal language for building agents. Core constructs: `fn`, `type`, `interface`, `test`.

---

## 1. Basics

```manuscript
// Comments (single-line only, no block comments)
// Indentation defines blocks (2 spaces recommended)
// No semicolons required

// Primitives
42  3.14  1e10               // number (also 0x1F, 0b1010, 1_000_000)
"hello"  """multiline"""     // string
true  false                  // bool
null                         // null
[1, 2, 3]                    // list[T]
{a: 1, b: 2}                 // map[K, V]
<1, 2, 3>  <>                // set[T]
b"binary"                    // bytes

// Variables
let x = 1                    // immutable
var y = 2                    // mutable

// Destructuring
let {name, age} = user
let [first, ...rest] = items
```

### Strings

```manuscript
"hello\nworld"               // escape sequences: \n \t \r \\ \" \u####
r"C:\path\file"              // raw string (no escaping)
r"""multiline raw"""
```

---

## 2. Operators

```manuscript
+ - * / % ^                  // arithmetic
== != < > <= >=              // comparison
and or not                   // logical
= += -= *= /= %=             // assignment
a ?? b                       // null coalesce
a?.b                         // optional chain
a!                           // null assertion
x is Type                    // type check (narrows in branches)
x as Type                    // type assertion
value | fn                   // pipe
...list                      // spread
list[0]  map["k"]  obj.f     // access
list[1:4]  list[::2]         // slice
list.length  str.length      // properties on built-ins
```

### Precedence (highest to lowest)

| Level | Operators |
|-------|-----------|
| 1 | `.` `[]` `()` `!` |
| 2 | `^` |
| 3 | `* / %` |
| 4 | `+ -` |
| 5 | `..` (range) |
| 6 | `== != < > <= >=` `is` `as` |
| 7 | `not` |
| 8 | `and` |
| 9 | `or` |
| 10 | `??` |
| 11 | `\|` (pipe) |
| 12 | `= += -= *= /= %=` |

---

## 3. Control Flow

```manuscript
// Conditionals
if cond then stmt                              // inline
if cond
  body
else if other
  body
else
  body

let x = if cond then a else b                  // expression

// Guards (unwrap or exit)
if let user = get_user(id) else return "Not found"
if let Ok(data) = parse(input) else return Error("failed")

// Match
match value
  Pattern => result
  Pattern if guard => result                   // with guard
  200..299 => "success"                        // range
  _ => default

// Loops
for item in items
  body
for i in 0..10                   // range: start inclusive, end exclusive (0..3 => 0,1,2)
  body
for                               // infinite
  if done then break
// break exits loop, continue skips to next iteration

// Error handling
try
  risky()
catch e
  handle(e)

// Cleanup
defer file.close()           // runs at scope exit, even on error

// Generator
fn seq()
  yield 1
  yield 2
```

---

## 4. Functions

```manuscript
fn name(param: type, opt?: type, def: type = value): return_type
  body

fn add(a: number, b: number): number
  a + b                      // last expression is return value

fn validate(x: number): number
  if x < 0 then return 0     // explicit early return
  x * 2

// Variadic
fn log(level: string, ...messages: list[string])

// Lambda
(x) => x * 2
(a, b) => a + b
```

### Tool Comments

```manuscript
// Read a file's contents
// Args:
//   path: The file path to read
fn read_file(path: string): string using (fs: Filesystem)
  fs.read(path)
```

---

## 5. Types

```manuscript
// Alias
type UserID = string
type Handler = fn(Request): Response

// Definition
type User
  id: number                 // required
  name: string
  email?: string             // optional
  role: string = "user"      // default
  display: () => "{name}"    // computed

// Methods
type Counter
  value: number = 0
  fn increment()
    value = value + 1
  fn get(): number
    value

// Type embedding 
// Capitalized type name on its own line embeds that type; fields and methods are promoted
type Animal
  name: string
  age: number
  fn speak(): string
    "{name} says hello"

type Dog
  Animal
  breed: string
  fn bark(): string
    "{name} barks!"

let dog = Dog(Animal("Buddy", 3), "Golden Retriever")
dog.name          // promoted from Animal
dog.speak()       // promoted method
dog.Animal.name   // direct access to embedded value
// Constructor args: embedded types first (in declaration order), then own fields
// Own fields/methods shadow promoted ones; use obj.EmbeddedType.member to access embedded
// Multiple embeds: if two embeds promote the same member name, use explicit access (obj.A.member)

// Interface: method signatures only (no bodies). Types satisfy interfaces implicitly (Go-style).
interface Serializable
  fn serialize(): string
  fn deserialize(data: string)

// Interface embedding: list an interface name on its own line; its methods are promoted
interface Reader
  fn read(): string
interface Writer
  fn write(data: string): void
interface ReadWriter
  Reader
  Writer
  fn read(): string   // own method shadows Reader.read

// Concrete types must give every method a body. No implements keyword.
type JsonDoc
  data: string
  fn serialize(): string
    data
  fn deserialize(s: string)
    data = s

fn process(s: Serializable): string
  s.serialize()

let doc = JsonDoc(data: "{}")
process(doc)   // OK: JsonDoc satisfies Serializable

// Construction (positional or named; cannot mix)
let user = User(id: 1, name: "Alice")
let p = Point(3, 4)
let q = Person(age: 30, name: "Alice")
```

### Unions

```manuscript
type Message = Text or Image or File
type Status = "pending" or "done"

match msg
  Text as t => t.content
  Image as i => i.url
```

### Generics

```manuscript
fn map[T, U](items: list[T], f: fn(T): U): list[U]
type Box[T]
  value: T

// Constraints
fn sort[T](items: list[T]): list[T] where T: Comparable

// Built-in generic types
list[T]                      // ordered collection
map[K, V]                    // key-value mapping
set[T]                       // unique values (literal: <a, b, c> or <>)
fn(A, B): R                  // function type
T?                           // optional (T or null)
Promise[T]                   // result of spawn; consume with race()
```

### Error Type

```manuscript
type Error
  message: string
  cause?: Error

// throw creates an Error
throw("something went wrong")
throw(Error(message: "failed", cause: prev_error))
```

---

## 6. Modules

```manuscript
// ms.toml (project root)
src = "src"    // directory where .ms files live (default "src")
```

```manuscript
// Imports (logical paths, local-first)
import { Coder } from "agents/coder"
import { Claude } from "anthropic"
import { helper } from "pkg:utils"     // force external

// Exports (all public by default, _ = private)
fn helper()                  // exported
fn _internal()               // private

// Entry point
fn main()
  // program starts here
```

---

## 7. Capabilities

Dependency injection via context types and `with`. Compiler verifies all requirements statically.

### Defining context types

Use `type` or `interface` for capability types; use them in `using` clauses and provide them in `with` blocks. Types used in `with` can have fields and methods (including `close()` for cleanup when the value is used in `with`).

```manuscript
type Filesystem
  fn read(path: string): string
  fn write(path: string, content: string): void

type Logger
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"
  fn close(): void
```

### Declaring Dependencies

```manuscript
fn read(path: string) using (fs: Filesystem)
  fs.read(path)

fn process(task: string) using (Filesystem)     // pass-through
  read("config.txt")

fn deploy(code: string) using (fs: Filesystem, sh: Shell)
  fs.write("app.js", code)
  sh.exec("node app.js")
```

### Defining Capability Groups

```manuscript
capabilities production
  llm = Claude(model: "opus")
  fs = LocalFilesystem()
  shell = LocalShell()
  
  fn exit(error?: Error)     // cleanup
    llm.close()

capabilities testing
  llm = MockLLM()
  fs = MockFilesystem()
```

### Using Capabilities

```manuscript
with production()
  agent.run("hello")

with let prod = production()
  prod.llm.call("hello")

with Logger("OP")              // anonymous: context available to using functions only
  greet("world")

with let log = Logger("OP")     // named: use log inside block and in using functions
  print(log.log("ok"))

with myResource                // pre-created value; type must have close(), called at block exit
  do_work()
```

Any type with a `close()` method is closable: used in `with`, `close()` runs at block exit (including on error). Context types often implement `close()` for cleanup.

### Compiler Inference

```manuscript
fn low() using (fs: Filesystem)
  fs.read("x")

fn mid()                     // inferred: requires Filesystem
  low()

fn high()                    // inferred: requires Filesystem
  mid()

high()                       // ERROR: Filesystem not in scope
with production()
  high()                     // OK
```

### Override Constraint

Method overrides cannot add capabilities (can use same or fewer):

```manuscript
type Handler
  fn handle(data: Data) using (fs: Filesystem)
```

---

## 8. Agents

```manuscript
agent name using (capabilities)
  field: type
  system: () => "..."                // computed prompt
  context: () => "..."               // per-turn context
  tools: [fn1, fn2]
  config: AgentConfig(max_turns: 50)
  
  fn on_init()
  fn on_turn_end(turn: Turn)
```

### Example

```manuscript
agent coder using (fs: Filesystem, sh: Shell)
  task: string
  system: () => "You are a coder. Task: {task}"
  tools: [read_file, write_file, run_command]
  files_modified: list = []
  
  fn on_turn_end(turn: Turn)
    for call in turn.tool_calls
      if call.name == "write_file"
        files_modified.push(call.args.path)
```

### Running

```manuscript
let c = coder(task: "Build API")

// Streaming
for chunk in c.stream("Start")
  print(chunk.text)

// Blocking
let result = c.run("Start")

// With reasoning
for chunk in c.stream("Fix bug", reasoning: true)
  match chunk.type
    "thinking" => log(chunk.text)
    "text" => print(chunk.text)

// Multi-turn
let chat = c.start()
chat.send("Hello")
chat.send("Follow up")
chat.end()
```

---

## 9. Concurrency

```manuscript
// spawn: start a task, get Promise[T]. Must consume with race() (or pass along until consumed)
let task = spawn work(42)
race([task])                  // wait for one; result is the value

fn work(n: number): number
  n * 2

// Promise[T] in types and functions
fn create_task(): Promise[number]
  let t = spawn work(10)
  t

```

---

## 10. Testing

```manuscript
test "description"
  let x = 1 + 1
  assert x == 2

test "with variables"
  let name = "Alice"
  assert len(name) == 5

test "with capabilities"
  with let llm = MockLLM()
    let result = agent.run("hello")
    assert result != null
```

`assert` is an expression — returns value if truthy, fails test otherwise:

```manuscript
let data = assert parse(json)           // unwrap or fail
let user = assert data.user, "no user"  // with message
```

---

## 11. Templates

```manuscript
"Hello, {name}"

"""
{if admin}Admin panel{else}User view{end}
{for item in items}- {item.name}{end}
"""
```

---

## Quick Reference

### Core Constructs

| Construct | Purpose |
|-----------|---------|
| `fn` | Function |
| `type` | Data structure |
| `interface` | Method signatures; types satisfy implicitly |
| `test` | Test cases |

### Type Fields

| Syntax | Meaning |
|--------|---------|
| `field: type` | Required |
| `field?: type` | Optional |
| `field: type = value` | Default |
| `field: () => expr` | Computed |
| `TypeName` (line alone) | Embedded type; members promoted, access via `obj.TypeName.member` |

### Capabilities

| Syntax | Meaning |
|--------|---------|
| `using (Type)` | Pass-through |
| `using (name: Type)` | Direct use |
| `with context()` | Provide scope |

### Control Flow

| Syntax | Meaning |
|--------|---------|
| `if cond then stmt` | Inline guard |
| `if let x = e else return` | Unwrap or exit |
| `defer stmt` | Cleanup at scope exit |
| `match x` | Pattern match |

### Operators

| Syntax | Meaning |
|--------|---------|
| `a ?? b` | Null coalesce |
| `a?.b` | Optional chain |
| `a!` | Null assertion |
| `x is T` | Type check |
| `x as T` | Type assert |
| `a \| fn` | Pipe |
| `...x` | Spread |
