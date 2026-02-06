// ============================================
// Manuscript Standard Library
// ============================================

// ============================================
// Closable (for with/using)
// ============================================

interface Closable
  fn close(): void

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
  fn entries(): list[list[unknown]]
  // Removes all entries
  fn clear(): void

extern type set[T]
  size: number
  // Adds item to set, returns set for chaining
  fn add(item: T): set[T]
  // Returns true if item exists
  fn has(item: T): bool
  // Deletes item, returns true if existed
  fn delete(item: T): bool
  // Removes all items
  fn clear(): void
  // Returns list of items
  fn values(): list[T]
  // Returns list of [value, value] pairs
  fn entries(): list[list[T]]
  // Same as values for set
  fn keys(): list[T]
  // Calls f for each element
  fn forEach(f: fn(T): void): void

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
extern fn print(...args: unknown): void
// Logs values for debugging
extern fn log(...args: unknown): void

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
extern fn entries[K, V](m: map[K, V]): list[list[unknown]]
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
extern fn race[T](promises: list[Promise[T]]): Promise[T]
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
  let result = [] as list[T]
  for i in 0..min(n, len(list))
    result.push(list[i])
  result

// Returns all but the first n elements
fn drop[T](list: list[T], n: number): list[T]
  let result = [] as list[T]
  for i in n..len(list)
    result.push(list[i])
  result

// Returns a reversed copy of the list
fn reverse[T](list: list[T]): list[T]
  let result = [] as list[T]
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
  let result = [] as list[T]
  for item in list
    let key = to_str(item)
    if not seen[key]
      seen[key] = true
      result.push(item)
  result

// Flattens a list of lists into one list
fn flatten[T](lists: list[list[T]]): list[T]
  let result = [] as list[T]
  for list in lists
    for item in list
      result.push(item)
  result

// Pairs elements from two lists
fn zip[T, U](a: list[T], b: list[U]): list[list[unknown]]
  let result = [] as list[list[unknown]]
  let n = min(len(a), len(b))
  for i in 0..n
    result.push([a[i], b[i]])
  result

// Concatenates multiple lists into one
fn concat[T](...lists: list[list[T]]): list[T]
  let result = [] as list[T]
  for list in lists
    for item in list
      result.push(item)
  result

// Returns list of integers [start, end)
fn range(start: number, end: number): list[number]
  let result = [] as list[number]
  for i in start..end
    result.push(i)
  result

// Returns a portion of the list
fn slice[T](list: list[T], start: number, end?: number): list[T]
  let e = end ?? len(list)
  let result = [] as list[T]
  for i in start..e
    result.push(list[i])
  result

// Transforms each element using f
fn map[T, U](list: list[T], f: fn(T): U): list[U]
  let result = [] as list[U]
  for item in list
    result.push(f(item))
  result

// Calls f for each element
fn each[T](list: list[T], f: fn(T): void): void
  for item in list
    f(item)

// Keeps elements where pred returns true
fn filter[T](list: list[T], pred: fn(T): bool): list[T]
  let result = [] as list[T]
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
  var result = {} as map[K, list[T]]
  for item in list
    let key = f(item)
    if not result[key]
      result[key] = [] as list[T]
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
extern fn set[T](list: list[T]): set[T]
// Returns union of two sets
extern fn union[T](a: set[T], b: set[T]): set[T]
// Returns intersection of two sets
extern fn intersect[T](a: set[T], b: set[T]): set[T]
// Returns elements in a but not in b
extern fn difference[T](a: set[T], b: set[T]): set[T]
// Returns true if a is subset of b
extern fn is_subset[T](a: set[T], b: set[T]): bool

// Result type for error handling
type Result[T, E]
  ok: bool
  value?: T
  error?: E

// Creates a success Result
fn ok[T](value: T): Result[T, never]
  Result(ok: true, value: value)

// Creates an error Result
fn err[E](error: E): Result[never, E]
  Result(ok: false, error: error)

// Throws if condition is false
fn assert(condition: bool, message?: string): void
  if not condition
    panic(message ?? "Assertion failed")

// Deep equality check using JSON
fn equals[T](a: T, b: T): bool
  to_json(a) == to_json(b)
