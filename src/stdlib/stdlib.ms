// ============================================
// Manuscript Standard Library
// ============================================

// ============================================
// Built-in Keywords
// ============================================

// Agent keyword - defines AI agents with tools and capabilities
keyword agent = type

// Context/Capabilities keyword - defines capability bundles for dependency injection
keyword context = type

keyword capabilities = type

// Enum keyword - defines enumerated types with named constants
keyword enum = type

// ============================================
// Primitive Type Methods (built-in)
// ============================================

extern type string
  length: number
  // Converts to uppercase
  fn upper(): string
  // Converts to lowercase
  fn lower(): string
  // Removes leading/trailing whitespace
  fn trim(): string
  // Splits by delimiter
  fn split(sep: string): list[string]
  // Returns true if contains substring
  fn contains(s: string): bool
  // Returns true if starts with prefix
  fn starts_with(prefix: string): bool
  // Returns true if ends with suffix
  fn ends_with(suffix: string): bool
  // Replaces occurrences of old with new
  fn replace(old: string, new: string): string
  // Returns a portion of the string
  fn slice(start: number, end?: number): string
  // Returns character at index
  fn char_at(index: number): string?
  // Returns index of substring, or null
  fn index_of(s: string): number?
  // Repeats string n times
  fn repeat(n: number): string
  // Pads at start to given length
  fn pad_start(len: number, char?: string): string
  // Pads at end to given length
  fn pad_end(len: number, char?: string): string
  // Returns list of characters
  fn chars(): list[string]

extern type list[T]
  length: number
  // Adds item to end, returns the list
  fn push(item: T): list[T]
  // Removes and returns last element
  fn pop(): T?
  // Removes and returns first element
  fn shift(): T?
  // Returns true if list contains item
  fn contains(item: T): bool
  // Returns index of item, or null
  fn index_of(item: T): number?
  // Joins elements with separator
  fn join(sep?: string): string
  // Returns reversed list
  fn reverse(): list[T]
  // Returns a portion of the list
  fn slice(start: number, end?: number): list[T]
  // Transforms each element
  fn map[U](f: fn(T): U): list[U]
  // Keeps elements matching predicate
  fn filter(f: fn(T): bool): list[T]
  // Folds list to single value
  fn reduce[U](f: fn(U, T): U, init: U): U
  // Returns first matching element
  fn find(f: fn(T): bool): T?
  // Returns true if all match predicate
  fn every(f: fn(T): bool): bool
  // Returns true if any matches predicate
  fn some(f: fn(T): bool): bool
  // Returns first element
  fn first(): T?
  // Returns last element
  fn last(): T?
  // Returns true if list is empty
  fn is_empty(): bool
  // Returns sorted list
  fn sort(cmp?: fn(T, T): number): list[T]

extern type map[K, V]
  size: number
  // Returns value for key, or null
  fn get(key: K): V?
  // Sets key to value
  fn set(key: K, value: V): void
  // Returns true if key exists
  fn has(key: K): bool
  // Deletes key, returns true if existed
  fn delete(key: K): bool
  // Returns list of keys
  fn keys(): list[K]
  // Returns list of values
  fn values(): list[V]
  // Returns list of [key, value] pairs
  fn entries(): list[list[any]]
  // Removes all entries
  fn clear(): void

extern type set[T]
  size: number
  // Adds item to set
  fn add(item: T): void
  // Returns true if item exists
  fn has(item: T): bool
  // Deletes item, returns true if existed
  fn delete(item: T): bool
  // Removes all items
  fn clear(): void
  // Returns list of items
  fn values(): list[T]

// ============================================
// Built-in Types
// ============================================

type Error
  message: string
  cause: Error?
  stack: string?

extern type Context
  fn exit(): void

// ============================================
// Intrinsic Functions (implemented in TypeScript)
// ============================================

// I/O
// Prints values to stdout
extern fn print(...args: any): void
// Logs values for debugging
extern fn log(...args: any): void

// Math
// Returns the square root
extern fn sqrt(n: number): number
// Returns base raised to exp power
extern fn pow(base: number, exp: number): number
// Rounds down to nearest integer
extern fn floor(n: number): number
// Rounds up to nearest integer
extern fn ceil(n: number): number
// Rounds to nearest integer
extern fn round(n: number): number
// Returns random float between 0 and 1
extern fn random(): number
// Returns random integer in range [min, max)
extern fn random_int(min: number, max: number): number

// Type operations
// Returns the type name as a string
extern fn typeof[T](x: T): string
// Creates a deep copy of the value
extern fn clone[T](x: T): T
// Returns a hash code for the value
extern fn hash[T](x: T): number

// Conversion
// Converts value to string
extern fn to_str[T](x: T): string
// Parses string as number
extern fn to_num(s: string): number
// Serializes value to JSON string
extern fn to_json[T](x: T): string
// Parses JSON string to value
extern fn from_json[T](s: string): T

// Time
// Returns current timestamp in milliseconds
extern fn now(): number
// Pauses execution for given milliseconds
extern fn sleep(ms: number): void

// Collections
// Returns length/size of collection
extern fn len[T](x: T): number
// Returns list of map keys
extern fn keys[K, V](m: map[K, V]): list[K]
// Returns list of map values
extern fn values[K, V](m: map[K, V]): list[V]
// Returns list of [key, value] pairs
extern fn entries[K, V](m: map[K, V]): list[list[any]]
// Returns a sorted copy of the list
extern fn sort[T](list: list[T]): list[T]

// ============================================
// Async Types
// ============================================

// Represents an asynchronous computation that resolves to T
extern type Promise[T]

// Represents a lazy sequence of values (generator output)
extern type Stream[T]

// Concurrency
// Returns first promise to resolve
extern fn race(promises: list[Promise[any]]): Promise[any]
// Fails promise if it takes longer than ms
extern fn timeout[T](ms: number, p: Promise[T]): Promise[T]
// Returns a promise that resolves after ms
extern fn delay(ms: number): Promise[void]

// ============================================
// Channel
// ============================================

extern type Channel[T]
  buffer?: number
  // Sends a value to the channel (blocks if full)
  fn send(value: T): void
  // Receives a value from the channel (blocks if empty)
  fn receive(): T?
  // Closes the channel
  fn close(): void
  // Non-blocking send, returns false if channel is full
  fn try_send(value: T): bool
  // Non-blocking receive, returns null if empty
  fn try_receive(): T?
  // Returns true if the channel is closed
  fn isClosed(): bool

// ============================================
// LLM Capabilities
// ============================================

extern type Claude
  Context
  model?: string
  apiKey?: string
  maxTokens?: number
  // Sends a prompt and returns the response
  fn ask(prompt: string): string
  // Completes a chat with messages
  fn complete(messages: list[any]): any
  // Streams a chat completion
  fn stream(messages: list[any]): any
  fn exit(): void

extern type GPT
  Context
  model?: string
  apiKey?: string
  maxTokens?: number
  baseURL?: string
  // Sends a prompt and returns the response
  fn ask(prompt: string): string
  // Completes a chat with messages
  fn complete(messages: list[any]): any
  // Streams a chat completion
  fn stream(messages: list[any]): any
  fn exit(): void

extern type MockLLM
  Context
  responses?: list[any]
  defaultReply?: string
  delay?: number
  // Sends a prompt and returns the mock response
  fn ask(prompt: string): string
  // Completes a chat with mock messages
  fn complete(messages: list[any]): any
  // Streams a mock chat completion
  fn stream(messages: list[any]): any
  // Adds a mock response pattern
  fn addResponse(pattern: string, reply: string): void
  fn exit(): void

// ============================================
// Filesystem Capabilities
// ============================================

extern type LocalFilesystem
  Context
  root?: string
  // Reads file contents as string
  fn read(path: string): string
  // Writes string content to file
  fn write(path: string, content: string): void
  // Returns true if path exists
  fn exists(path: string): bool
  // Lists directory contents
  fn list(path: string): list[any]
  // Finds files matching glob pattern
  fn glob(pattern: string): list[string]
  // Creates directory recursively
  fn mkdir(path: string): void
  // Removes file or directory
  fn remove(path: string): void
  // Copies file from src to dest
  fn copy(src: string, dest: string): void
  // Moves file from src to dest
  fn move(src: string, dest: string): void
  fn exit(): void

extern type MockFilesystem
  Context
  files?: map[string, string]
  fn read(path: string): string
  fn write(path: string, content: string): void
  fn exists(path: string): bool
  fn list(path: string): list[any]
  fn glob(pattern: string): list[string]
  fn mkdir(path: string): void
  fn remove(path: string): void
  fn copy(src: string, dest: string): void
  fn move(src: string, dest: string): void
  // Sets mock file content directly
  fn setFile(path: string, content: string): void
  fn exit(): void

// Filesystem alias for LocalFilesystem
extern type Filesystem
  Context
  root?: string
  fn read(path: string): string
  fn write(path: string, content: string): void
  fn exists(path: string): bool
  fn list(path: string): list[any]
  fn glob(pattern: string): list[string]
  fn mkdir(path: string): void
  fn remove(path: string): void
  fn copy(src: string, dest: string): void
  fn move(src: string, dest: string): void
  fn exit(): void

// ============================================
// Shell Capabilities
// ============================================

extern type LocalShell
  Context
  shell?: string
  cwd?: string
  // Executes command and returns result
  fn exec(command: string): any
  // Starts command with streaming output
  fn start(command: string): any
  // Finds path to command executable
  fn which(command: string): string?
  fn exit(): void

extern type MockShell
  Context
  commands?: list[any]
  cwd?: string
  env?: map[string, string]
  fn exec(command: string): any
  fn start(command: string): any
  fn which(command: string): string?
  // Adds mock command response
  fn addCommand(pattern: string, result: any): void
  fn exit(): void

// Shell alias for LocalShell
extern type Shell
  Context
  shell?: string
  cwd?: string
  fn exec(command: string): any
  fn start(command: string): any
  fn which(command: string): string?
  fn exit(): void

// ============================================
// HTTP Capabilities
// ============================================

extern type FetchHTTP
  Context
  baseURL?: string
  headers?: map[string, string]
  timeout?: number
  fn get(url: string): any
  fn post(url: string): any
  fn put(url: string): any
  fn patch(url: string): any
  fn delete(url: string): any
  // Performs GET and parses JSON response
  fn getJSON(url: string): any
  // Performs POST with JSON body
  fn postJSON(url: string, data: any): any
  fn exit(): void

extern type MockHTTP
  Context
  responses?: list[any]
  fn get(url: string): any
  fn post(url: string): any
  fn put(url: string): any
  fn patch(url: string): any
  fn delete(url: string): any
  fn getJSON(url: string): any
  fn postJSON(url: string, data: any): any
  // Adds mock HTTP response
  fn addResponse(pattern: string, response: any): void
  fn exit(): void

// HTTP alias for FetchHTTP
extern type HTTP
  Context
  baseURL?: string
  headers?: map[string, string]
  timeout?: number
  fn get(url: string): any
  fn post(url: string): any
  fn put(url: string): any
  fn patch(url: string): any
  fn delete(url: string): any
  fn getJSON(url: string): any
  fn postJSON(url: string, data: any): any
  fn exit(): void

// Errors
// Throws an unrecoverable error
extern fn panic(message: string): never
// Creates an Error with optional cause
extern fn error(message: string, cause?: Error): Error

// ============================================
// Pure Functions (implemented in Manuscript)
// ============================================

// Returns the absolute value
fn abs(n: number): number
  if n < 0 then -n else n

// Returns the smaller of two numbers
fn min(a: number, b: number): number
  if a < b then a else b

// Returns the larger of two numbers
fn max(a: number, b: number): number
  if a > b then a else b

// Constrains n to range [lo, hi]
fn clamp(n: number, lo: number, hi: number): number
  min(max(n, lo), hi)

// Returns the first element, or null
fn first[T](list: list[T]): T?
  if len(list) > 0 then list[0] else null

// Returns the last element, or null
fn last[T](list: list[T]): T?
  if len(list) > 0 then list[len(list) - 1] else null

// Returns the first n elements
fn take[T](list: list[T], n: number): list[T]
  let result = []
  for i in 0..min(n, len(list))
    result.push(list[i])
  result

// Returns all but the first n elements
fn drop[T](list: list[T], n: number): list[T]
  let result = []
  for i in n..len(list)
    result.push(list[i])
  result

// Returns a reversed copy of the list
fn reverse[T](list: list[T]): list[T]
  let result = []
  for i in 0..len(list)
    result.push(list[len(list) - 1 - i])
  result

// Returns true if list contains item
fn contains[T](list: list[T], item: T): bool
  for x in list
    if x == item
      return true
  false

// Returns list with duplicates removed
fn unique[T](list: list[T]): list[T]
  let seen = {}
  let result = []
  for item in list
    let key = to_str(item)
    if not seen[key]
      seen[key] = true
      result.push(item)
  result

// Flattens a list of lists into one list
fn flatten[T](lists: list[list[T]]): list[T]
  let result = []
  for list in lists
    for item in list
      result.push(item)
  result

// Pairs elements from two lists
fn zip[T, U](a: list[T], b: list[U]): list[list[any]]
  let result = []
  let n = min(len(a), len(b))
  for i in 0..n
    result.push([a[i], b[i]])
  result

// Concatenates multiple lists into one
fn concat[T](...lists: list[list[T]]): list[T]
  let result = []
  for list in lists
    for item in list
      result.push(item)
  result

// Returns list of integers [start, end)
fn range(start: number, end: number): list[number]
  let result = []
  for i in start..end
    result.push(i)
  result

// Returns a portion of the list
fn slice[T](list: list[T], start: number, end?: number): list[T]
  let e = end ?? len(list)
  let result = []
  for i in start..e
    result.push(list[i])
  result

// Transforms each element using f
fn map[T, U](list: list[T], f: fn(T): U): list[U]
  let result = []
  for item in list
    result.push(f(item))
  result

// Calls f for each element
fn each[T](list: list[T], f: fn(T): void): void
  for item in list
    f(item)

// Keeps elements where pred returns true
fn filter[T](list: list[T], pred: fn(T): bool): list[T]
  let result = []
  for item in list
    if pred(item)
      result.push(item)
  result

// Folds list into a single value
fn reduce[T, U](list: list[T], init: U, f: fn(U, T): U): U
  var acc = init
  for item in list
    acc = f(acc, item)
  acc

// Returns first element matching pred
fn find[T](list: list[T], pred: fn(T): bool): T?
  for item in list
    if pred(item)
      return item
  null

// Returns true if any element matches
fn any[T](list: list[T], pred: fn(T): bool): bool
  for item in list
    if pred(item)
      return true
  false

// Returns true if all elements match
fn all[T](list: list[T], pred: fn(T): bool): bool
  for item in list
    if not pred(item)
      return false
  true

// Groups elements by key from f
fn group_by[T, K](list: list[T], f: fn(T): K): map[K, list[T]]
  var result = {}
  for item in list
    let key = f(item)
    if not result[key]
      result[key] = []
    result[key].push(item)
  result

// Sorts list by key from f
fn sort_by[T, K](list: list[T], f: fn(T): K): list[T]
  let pairs = map(list, (item) => [f(item), item])
  let sorted = sort(pairs)
  map(sorted, (pair) => pair[1] as T)

// String functions
// Converts string to uppercase
extern fn upper(s: string): string
// Converts string to lowercase
extern fn lower(s: string): string
// Removes leading/trailing whitespace
extern fn trim(s: string): string
// Splits string by delimiter
extern fn split(s: string, delim: string): list[string]
// Joins strings with delimiter
extern fn join(list: list[string], delim: string): string
// Replaces occurrences of old with new
extern fn replace(s: string, old: string, replacement: string): string
// Returns true if string starts with prefix
extern fn starts_with(s: string, prefix: string): bool
// Returns true if string ends with suffix
extern fn ends_with(s: string, suffix: string): bool
// Returns a portion of the string
extern fn substring(s: string, start: number, end?: number): string
// Returns true if string matches regex pattern
extern fn matches(s: string, pattern: string): bool

// Creates a set from a list
fn set[T](list: list[T]): set[T]
  let result = {}
  for item in list
    result[item] = true
  result

// Returns union of two sets
fn union[T](a: set[T], b: set[T]): set[T]
  let result = {}
  for k in keys(a)
    result[k] = true
  for k in keys(b)
    result[k] = true
  result

// Returns intersection of two sets
fn intersect[T](a: set[T], b: set[T]): set[T]
  let result = {}
  for k in keys(a)
    if b[k]
      result[k] = true
  result

// Returns elements in a but not in b
fn difference[T](a: set[T], b: set[T]): set[T]
  let result = {}
  for k in keys(a)
    if not b[k]
      result[k] = true
  result

// Returns true if a is subset of b
fn is_subset[T](a: set[T], b: set[T]): bool
  for k in keys(a)
    if not b[k]
      return false
  true

// Result type for error handling
type Result[T, E]
  ok: bool
  value?: T
  error?: E

// Creates a success Result
fn ok[T](value: T): Result[T, never]
  { ok: true, value: value }

// Creates an error Result
fn err[E](error: E): Result[never, E]
  { ok: false, error: error }

// Throws if condition is false
fn assert(condition: bool, message?: string): void
  if not condition
    panic(message ?? "Assertion failed")

// Deep equality check using JSON
fn equals[T](a: T, b: T): bool
  to_json(a) == to_json(b)
