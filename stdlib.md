# Manuscript Standard Library

Built-in types, functions, and patterns. All available without imports.

---

## 1. Built-in Functions

### Collections

```manuscript
len(x)                   // length of list, string, map
keys(map)  values(map)   // extract keys/values
entries(map)             // list of {key, value}
contains(list, item)     // membership check
unique(list)             // remove duplicates
flatten(list)            // flatten nested
sort(list)  reverse(list)
first(list)  last(list)  // or null
take(list, n)  drop(list, n)
zip(a, b)                // pair elements
range(start, end)        // number sequence

// List methods
list.push(item)          // add to end, returns list
list.pop(): T?           // remove and return last
list.shift(): T?         // remove and return first
list.insert(i, item)     // insert at index
list.remove(i): T        // remove at index
list.clear()             // remove all
list.index_of(item): number?
```

### Higher-Order

```manuscript
each(list, fn)           // transform: [T] → [U]
filter(list, pred)       // keep matching
reduce(list, init, fn)   // fold to single value
find(list, pred)         // first match or null
any(list, pred)          // true if any match
all(list, pred)          // true if all match
group_by(list, fn)       // group by key
sort_by(list, fn)        // sort by key
```

### Strings

```manuscript
upper(s)  lower(s)  trim(s)
split(s, delim)          // → list
join(list, delim)        // → string
replace(s, old, new)
starts_with(s, prefix)
ends_with(s, suffix)
substring(s, start, end?)
pad_start(s, len, char?)
pad_end(s, len, char?)
matches(s, pattern)      // regex

// String/List properties
str.length               // character count
list.length              // element count
```

### Numbers

```manuscript
abs(n)  min(a, b)  max(a, b)
floor(n)  ceil(n)  round(n)
clamp(n, lo, hi)
sqrt(n)  pow(base, exp)
sin(n)  cos(n)  tan(n)
log(n)  log10(n)  exp(n)
random()                     // 0.0 to 1.0
random_int(min, max)         // inclusive
```

### Regex

```manuscript
regex_match(s, pattern): Match?           // first match
regex_find_all(s, pattern): list[Match]   // all matches
regex_replace(s, pattern, replacement): string
regex_split(s, pattern): list[string]

type Match
  text: string               // matched text
  index: number              // position
  groups: list[string]       // capture groups
```

### Sets

```manuscript
set(list)                    // create set from list
union(a, b)                  // a ∪ b
intersect(a, b)              // a ∩ b
difference(a, b)             // a - b
is_subset(a, b)              // a ⊆ b
```

### Conversion

```manuscript
to_str(x)  to_num(s)
to_json(x)  from_json(s)
```

### Utility

```manuscript
print(x)  log(x)
now()                    // timestamp (ms)
sleep(ms)
throw(msg)
typeof(x)                // "string", "number", "list", etc.
clone(x)                 // deep copy
equals(a, b)             // deep equality
hash(x)                  // hash code for any value
```

---

## 2. Error and Result Types

### Error

```manuscript
type Error
  message: string
  cause?: Error
  stack?: string

fn error(message: string, cause?: Error): Error
```

### Result

```manuscript
type Result[T, E]
  = Ok(value: T)
  or Err(error: E)

// Pattern match
match result
  Ok(v) => process(v)
  Err(e) => handle(e)

// Helpers
fn ok[T](value: T): Result[T, any]
fn err[E](e: E): Result[any, E]
```

---

## 3. Concurrency

### Promise

```manuscript
type Promise[T]
  fn then[U](f: fn(T): U): Promise[U]
  fn catch(f: fn(Error): T): Promise[T]
  fn finally(f: fn()): Promise[T]
```

### Functions

```manuscript
spawn[F](f: F): Promise[ReturnType[F]]   // start async
all(a, b, ...)                            // wait for all
race(...promises)                         // first to complete
any(...promises)                          // first success
timeout(ms, promise)                      // with timeout
delay(ms)                                 // sleep as promise
```

### Usage

```manuscript
// Sequential (implicit await)
let user = fetch_user(id)
let orders = fetch_orders(user)

// Parallel
let [users, orders] = all(
  spawn(fetch_users()),
  spawn(fetch_orders())
)

// With error handling
spawn(fetch(url)) | then(parse) | catch(handle)
```

---

## 4. Channels

Communication between concurrent operations.

```manuscript
type Channel[T]
  fn send(value: T)      // blocks if full
  fn receive(): T?       // null if closed
  fn close()
  fn throw(error: Error) // propagate error
  fn try_send(value: T): bool
  fn try_receive(): T?

fn Channel[T](buffer?: number): Channel[T]
```

### Patterns

```manuscript
// Basic
let ch = Channel[string]()
spawn(ch.send("hello"))
let msg = ch.receive()

// Iterate until closed
for msg in ch
  process(msg)

// Fan-in (many producers)
spawn(ch.send(fetch_a()))
spawn(ch.send(fetch_b()))
for result in ch
  process(result)

// Select (multiple channels)
match select(ch1, ch2, timeout: 5000)
  {channel: ch1, value: v} => handle1(v)
  {channel: ch2, value: v} => handle2(v)
  Timeout => handle_timeout()
```

### Helpers

```manuscript
select(...channels, timeout?)    // wait on multiple
merge(...channels)               // combine into one
map(channel, fn)                 // transform values
filter(channel, pred)            // filter values

type Broadcast[T]                // one-to-many
  fn subscribe(): Channel[T]
  fn send(value: T)
  fn close()
```

---

## 5. Capability Interfaces

### LLM

```manuscript
type LLM
  fn complete(messages: list, config?: LLMConfig): Stream[Chunk]
  fn embed(text: string): list[number]

type LLMConfig
  model?: string
  temperature?: number
  max_tokens?: number
  tools?: list

type Chunk
  type: string           // "text", "thinking", "tool_call", "done"
  text?: string
  tool?: string
  args?: map
```

### Filesystem

```manuscript
type Filesystem
  fn read(path: string): string
  fn write(path: string, content: string)
  fn exists(path: string): bool
  fn list(path: string): list[FileInfo]
  fn mkdir(path: string)
  fn remove(path: string)

type FileInfo
  name: string
  path: string
  is_dir: bool
  size: number
  modified: number           // timestamp
```

### Shell

```manuscript
type Shell
  fn exec(cmd: string, opts?: ShellOpts): ShellResult

type ShellOpts
  cwd?: string
  env?: map
  timeout?: number

type ShellResult
  stdout: string
  stderr: string
  code: number
```

### HTTP

```manuscript
type HTTP
  fn get(url: string, opts?: HTTPOpts): HTTPResponse
  fn post(url: string, body: any, opts?: HTTPOpts): HTTPResponse
  fn put(url: string, body: any, opts?: HTTPOpts): HTTPResponse
  fn delete(url: string, opts?: HTTPOpts): HTTPResponse

type HTTPOpts
  headers?: map
  timeout?: number

type HTTPResponse
  status: number
  headers: map
  body: string
```

### Database

```manuscript
type Database
  fn query(sql: string, params?: list): list
  fn insert(table: string, data: map): any
  fn update(table: string, where: map, data: map): number
  fn delete(table: string, where: map): number
  fn find(table: string, where: map): any?
```

### Server

```manuscript
type Server
  fn listen(port: number): Channel[Connection]
  fn stop()

type Connection
  request: Request
  fn respond(response: Response)

type Request
  method: string
  path: string
  headers: map
  query: map
  body: string

type Response
  status: number = 200
  headers: map = {}
  body: string = ""

// Usage
let server = Server()
let connections = server.listen(3000)

for conn in connections
  match conn.request.path
    "/" => conn.respond(Response(body: "Hello"))
    "/api" => conn.respond(Response(body: to_json(data)))
    _ => conn.respond(Response(status: 404, body: "Not found"))
```

### WebSocket

```manuscript
type WebSocket
  fn connect(url: string): WSConn
  fn listen(port: number): Channel[WSConn]

type WSConn
  incoming: Channel[string]    // messages from peer
  fn send(msg: string)
  fn close()

// Usage (client)
let ws = WebSocket().connect("ws://example.com")
spawn
  for msg in ws.incoming
    handle(msg)
ws.send("hello")

// Usage (server)
let conns = WebSocket().listen(8080)
for conn in conns
  spawn
    for msg in conn.incoming
      conn.send("echo: {msg}")
```

### TCP

```manuscript
type TCP
  fn connect(host: string, port: number): TCPConn
  fn listen(port: number): Channel[TCPConn]

type TCPConn
  incoming: Channel[bytes]     // data from peer
  fn write(data: bytes)
  fn close()

// Usage
let conns = TCP().listen(9000)
for conn in conns
  spawn
    for data in conn.incoming
      conn.write(process(data))
```

### Process

```manuscript
type Process
  fn spawn(cmd: string, args: list[string], opts?: ProcessOpts): Child

type ProcessOpts
  cwd?: string
  env?: map
  stdin?: string

type Child
  pid: number
  stdin: Channel[string]
  stdout: Channel[string]
  stderr: Channel[string]
  fn wait(): number        // exit code
  fn kill()
```

### Environment

```manuscript
type Env
  fn get(key: string): string?
  fn set(key: string, value: string)
  fn all(): map
  args: list[string]       // command line arguments
  cwd: string              // current working directory
```

### Path

```manuscript
fn path_join(...parts: list[string]): string
fn path_dir(path: string): string
fn path_base(path: string): string
fn path_ext(path: string): string
fn path_abs(path: string): string
fn path_rel(from: string, to: string): string
```

### Crypto

```manuscript
type Crypto
  fn hash(algo: string, data: string): string      // "sha256", "md5", etc.
  fn hmac(algo: string, key: string, data: string): string
  fn random_bytes(n: number): bytes
  fn uuid(): string
  fn encrypt(key: string, data: string): string    // AES
  fn decrypt(key: string, data: string): string
```

### Time

```manuscript
type DateTime
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
  ms: number
  timezone: string

fn now(): DateTime
fn parse_time(s: string, format?: string): DateTime
fn format_time(dt: DateTime, format: string): string
fn timestamp(dt: DateTime): number               // unix ms
fn from_timestamp(ms: number): DateTime
fn add_time(dt: DateTime, amount: number, unit: string): DateTime
fn diff_time(a: DateTime, b: DateTime, unit: string): number
```

### URL

```manuscript
type URL
  scheme: string
  host: string
  port?: number
  path: string
  query: map
  fragment?: string

fn parse_url(s: string): URL
fn build_url(url: URL): string
fn encode_uri(s: string): string
fn decode_uri(s: string): string
```

### Logging

```manuscript
type Logger
  fn debug(msg: string, data?: map)
  fn info(msg: string, data?: map)
  fn warn(msg: string, data?: map)
  fn error(msg: string, data?: map)
  fn with(data: map): Logger         // child logger with context

fn logger(name: string): Logger
```

### Bytes

```manuscript
type bytes                           // binary data

fn to_bytes(s: string): bytes
fn from_bytes(b: bytes): string
fn bytes_len(b: bytes): number
fn bytes_slice(b: bytes, start: number, end: number): bytes
fn bytes_concat(...parts: list[bytes]): bytes
fn base64_encode(b: bytes): string
fn base64_decode(s: string): bytes
fn hex_encode(b: bytes): string
fn hex_decode(s: string): bytes
```

### Streams

For processing large data without loading all into memory:

```manuscript
type Stream[T]
  fn next(): T?              // next item or null if done
  fn collect(): list[T]      // consume all into list
  fn take(n: number): Stream[T]
  fn skip(n: number): Stream[T]
  fn map[U](f: fn(T): U): Stream[U]
  fn filter(pred: fn(T): bool): Stream[T]

// File streaming
fn stream_file(path: string): Stream[string]       // line by line
fn stream_bytes(path: string, chunk: number): Stream[bytes]

// Usage
for line in stream_file("large.log")
  if line | contains("ERROR")
    process(line)
```

### Signals

```manuscript
type Signals
  shutdown: Channel[string]     // SIGTERM, SIGINT

// Usage
for sig in Signals.shutdown
  log("Received {sig}, shutting down...")
  server.stop()
  break
```

---

## 6. Context

Interface for `with` statement:

```manuscript
type Context
  fn enter(): Context
  fn exit(error?: Error)
```

### Built-in Contexts

```manuscript
// Tracing
type Trace extends Context
  name: string
  fn tag(key: string, value: any)
  fn event(name: string)

// Mutual exclusion
type Lock extends Context
  resource: any

// Database transaction
type Transaction extends Context using (db: Database)
  fn insert(table: string, data: map)
  fn commit()
```

### Usage

```manuscript
with Trace("operation") as t
  t.event("started")
  process()

with Lock(resource)
  modify(resource)

with Transaction(db) as tx
  tx.insert("users", data)
  tx.commit()
```

---

## 7. Agent Types

```manuscript
type Agent using (llm: LLM)
  system: string = ""
  context: fn(): string = () => ""
  tools: list = []
  config: AgentConfig = AgentConfig()
  
  // Lifecycle hooks
  fn on_init()
  fn on_turn_start(turn: Turn)
  fn on_turn_end(turn: Turn)
  fn on_terminate(summary: Summary)
  
  // Core methods
  fn run(input: string): string
  fn stream(input: string, reasoning?: bool)
  fn start(): Conversation

type AgentConfig
  max_turns: number = 100
  timeout: number = 300000
  temperature: number = 0.7
  model?: string

type Turn
  number: number
  messages: list
  response?: string
  tool_calls: list = []

type Summary
  turns: number
  duration: number
  final_response: string

type Conversation
  fn send(input: string)
  fn end()
```

---

## 8. Mocks (for testing)

```manuscript
type MockLLM
  responses: list       // [{match: regex, reply: string}]
  calls: list          // recorded for assertions

type MockFilesystem
  files: map           // {path: content}
  calls: list

type MockShell
  commands: map        // {cmd: {stdout, stderr, code}}
  calls: list

type MockHTTP
  responses: map       // {url: {status, body}}
  calls: list
```

### Usage

```manuscript
test "agent responds"
  llm = MockLLM(responses: [{match: ".*", reply: "Hello"}])
  fs = MockFilesystem(files: {"config.txt": "data"})
  
  let result = assert agent.run("hi")
  assert result == "Hello"
  assert llm.calls.length == 1
```

---

## 9. Patterns

### Cached (memoization)

```manuscript
fn cached[T](compute: fn(): T): fn(): T

let get_config = cached(() => load_config())
get_config()  // computes once, then cached
```

### Retry

```manuscript
fn retry[T](f: fn(): T, times: number = 3, delay: number = 1000): T

let result = retry(() => http.get(url), times: 3)
```

### Fallback

```manuscript
fn fallback[T](f: fn(): T, default: T): T

let result = fallback(() => parse(input), {})
```

---

## 10. Keywords

Stdlib-defined syntax shortcuts:

```manuscript
keyword capabilities = type extends Context
keyword agent = type extends Agent using (LLM)
keyword prompt = fn (): string
keyword model = type

sealed keyword enum = type
```

| Keyword | Expands To |
|---------|------------|
| `capabilities` | `type extends Context` |
| `agent` | `type extends Agent using (LLM)` |
| `prompt` | `fn (): string` (no capabilities) |
| `model` | `type` (no capabilities) |
| `enum` | `type` (sealed) |

---

## Meta Types

Type-level utilities for generics:

```manuscript
ReturnType[F]            // return type of function
Arguments[F]             // argument types
Awaited[T]               // unwrap Promise[T] → T
ElementType[L]           // element of list[T] → T
KeyType[M]               // key of map[K,V] → K
ValueType[M]             // value of map[K,V] → V
```
