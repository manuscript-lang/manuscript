# Manuscript Syntax v4.0

A minimal language for building agents. Four core constructs: `fn`, `type`, `keyword`, `test`.

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
for i in 0..10
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

### Docstrings (Tool Exposure)

```manuscript
fn read_file(path: string): string using (fs: Filesystem)
  """
  Read a file's contents.

  Args:
    path: The file path to read
  """
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

// Inheritance
type Admin extends User
  permissions: list[string]

// Multiple inheritance
type Duck extends Animal, Flyable, Swimmable

// Interface (methods without bodies)
type Serializable
  fn serialize(): string
  fn deserialize(data: string)

// Construction
let user = User(id: 1, name: "Alice")
```

### Enums

```manuscript
enum Status
  Pending = "pending"
  Done = "done"

let s = Status.Pending       // s == "pending"
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
set[T]                       // unique values
fn(A, B): R                  // function type
T?                           // optional (T or null)
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
// project.yml
name: my-agent
entry: main
source: { root: src }
dependencies: { anthropic: 1.0 }
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

Dependency injection via `Context` and `with`. Compiler verifies all requirements statically.

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

with production(), Trace("op")
  deploy(code)

with Trace("op") as t
  t.event("started")
```

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

type FileHandler extends Handler
  fn handle(data: Data) using (fs: Filesystem)   // OK
type SimpleHandler extends Handler
  fn handle(data: Data)                          // OK (fewer)
type NetHandler extends Handler
  fn handle(data: Data) using (http: HTTP)       // ERROR (adds)
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

## 9. Testing

```manuscript
test "description"
  llm = MockLLM(responses: [{match: ".*", reply: "Hi"}])
  fs = MockFilesystem(files: {"a.txt": "content"})
  
  let result = assert agent.run("hello")
  assert result == "Hi"

test "with capabilities" with testing()
  let result = assert agent.run("hello")
  assert result.length > 0
```

`assert` is an expression — returns value if truthy, fails test otherwise:

```manuscript
let data = assert parse(json)           // unwrap or fail
let user = assert data.user, "no user"  // with message
```

---

## 10. Keyword Declarations

Define syntax shortcuts:

```manuscript
keyword capabilities = type extends Context
keyword agent = type extends Agent using (LLM)
keyword prompt = fn (): string

// Sealed variants
sealed keyword enum = type                    // no extends, no using
sealed(using) keyword model = type            // extends OK, no using
```

| Modifier | Inheritance | Capabilities |
|----------|-------------|--------------|
| `sealed` | No | No |
| `sealed(using)` | Yes | No |
| `sealed(extends)` | No | Yes |
| *(none)* | Yes | Yes |

---

## 11. Templates

```manuscript
"Hello, {name}"

"""
{if admin}Admin panel{else}User view{end}
{for item in items}- {item.name}{end}
"""

// Include
prompt base(role: string)
  "You are a {role}."

agent helper
  system: "{include base('assistant')}"
```

---

## Quick Reference

### Core Constructs

| Construct | Purpose |
|-----------|---------|
| `fn` | Function |
| `type` | Data structure |
| `keyword` | Syntax shortcuts |
| `test` | Test cases |

### Type Fields

| Syntax | Meaning |
|--------|---------|
| `field: type` | Required |
| `field?: type` | Optional |
| `field: type = value` | Default |
| `field: () => expr` | Computed |

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
