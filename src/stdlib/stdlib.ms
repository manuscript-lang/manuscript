// ============================================
// Manuscript Standard Library
// ============================================

// ============================================
// Primitive Type Methods (built-in)
// ============================================

extern type string
  length: number
  fn upper(): string
    "Converts to uppercase."
  fn lower(): string
    "Converts to lowercase."
  fn trim(): string
    "Removes leading/trailing whitespace."
  fn split(sep: string): list[string]
    "Splits by delimiter."
  fn contains(s: string): bool
    "Returns true if contains substring."
  fn starts_with(prefix: string): bool
    "Returns true if starts with prefix."
  fn ends_with(suffix: string): bool
    "Returns true if ends with suffix."
  fn replace(old: string, new: string): string
    "Replaces occurrences of 'old' with 'new'."
  fn slice(start: number, end?: number): string
    "Returns a portion of the string."
  fn char_at(index: number): string?
    "Returns character at index."
  fn index_of(s: string): number?
    "Returns index of substring, or null."
  fn repeat(n: number): string
    "Repeats string n times."
  fn pad_start(len: number, char?: string): string
    "Pads at start to given length."
  fn pad_end(len: number, char?: string): string
    "Pads at end to given length."
  fn chars(): list[string]
    "Returns list of characters."

extern type list[T]
  length: number
  fn push(item: T): list[T]
    "Adds item to end; returns the list."
  fn pop(): T?
    "Removes and returns last element."
  fn shift(): T?
    "Removes and returns first element."
  fn contains(item: T): bool
    "Returns true if list contains item."
  fn index_of(item: T): number?
    "Returns index of item, or null."
  fn join(sep?: string): string
    "Joins elements with separator."
  fn reverse(): list[T]
    "Returns reversed list."
  fn slice(start: number, end?: number): list[T]
    "Returns a portion of the list."
  fn map[U](f: fn(T): U): list[U]
    "Transforms each element."
  fn filter(f: fn(T): bool): list[T]
    "Keeps elements matching predicate."
  fn reduce[U](f: fn(U, T): U, init: U): U
    "Folds list to single value."
  fn find(f: fn(T): bool): T?
    "Returns first matching element."
  fn every(f: fn(T): bool): bool
    "Returns true if all match predicate."
  fn some(f: fn(T): bool): bool
    "Returns true if any matches predicate."
  fn first(): T?
    "Returns first element."
  fn last(): T?
    "Returns last element."
  fn is_empty(): bool
    "Returns true if list is empty."
  fn sort(cmp?: fn(T, T): number): list[T]
    "Returns sorted list."

extern type map[K, V]
  size: number
  fn get(key: K): V?
    "Returns value for key, or null."
  fn set(key: K, value: V): void
    "Sets key to value."
  fn has(key: K): bool
    "Returns true if key exists."
  fn delete(key: K): bool
    "Deletes key; returns true if existed."
  fn keys(): list[K]
    "Returns list of keys."
  fn values(): list[V]
    "Returns list of values."
  fn entries(): list[list[any]]
    "Returns list of [key, value] pairs."
  fn clear(): void
    "Removes all entries."

extern type set[T]
  size: number
  fn add(item: T): void
    "Adds item to set."
  fn has(item: T): bool
    "Returns true if item exists."
  fn delete(item: T): bool
    "Deletes item; returns true if existed."
  fn clear(): void
    "Removes all items."
  fn values(): list[T]
    "Returns list of items."

// ============================================
// Built-in Types
// ============================================

type Error
  message: string
  cause: Error?
  stack: string?

type Context
  fn exit(): void

// ============================================
// Intrinsic Functions (implemented in TypeScript)
// ============================================

// I/O
extern fn print(...args: any): void
  "Prints values to stdout."
extern fn log(...args: any): void
  "Logs values for debugging."

// Math
extern fn sqrt(n: number): number
  "Returns the square root."
extern fn pow(base: number, exp: number): number
  "Returns base raised to exp power."
extern fn floor(n: number): number
  "Rounds down to nearest integer."
extern fn ceil(n: number): number
  "Rounds up to nearest integer."
extern fn round(n: number): number
  "Rounds to nearest integer."
extern fn random(): number
  "Returns random float between 0 and 1."
extern fn random_int(min: number, max: number): number
  "Returns random integer in range [min, max)."

// Type operations
extern fn typeof[T](x: T): string
  "Returns the type name as a string."
extern fn clone[T](x: T): T
  "Creates a deep copy of the value."
extern fn hash[T](x: T): number
  "Returns a hash code for the value."

// Conversion
extern fn to_str[T](x: T): string
  "Converts value to string."
extern fn to_num(s: string): number
  "Parses string as number."
extern fn to_json[T](x: T): string
  "Serializes value to JSON string."
extern fn from_json[T](s: string): T
  "Parses JSON string to value."

// Time
extern fn now(): number
  "Returns current timestamp in milliseconds."
extern fn sleep(ms: number): void
  "Pauses execution for given milliseconds."

// Collections
extern fn len[T](x: T): number
  "Returns length/size of collection."
extern fn keys[K, V](m: map[K, V]): list[K]
  "Returns list of map keys."
extern fn values[K, V](m: map[K, V]): list[V]
  "Returns list of map values."
extern fn entries[K, V](m: map[K, V]): list[list[any]]
  "Returns list of [key, value] pairs."
extern fn sort[T](list: list[T]): list[T]
  "Returns a sorted copy of the list."

// Concurrency
extern fn race(promises: list[promise[any]]): promise[any]
  "Returns first promise to resolve."
extern fn timeout[T](ms: number, promise: promise[T]): promise[T]
  "Fails promise if it takes longer than ms."
extern fn delay(ms: number): promise[void]
  "Returns a promise that resolves after ms."

// Channels - Channel[T] is a type with extern methods
type Channel[T]
  buffer?: number
  extern fn send(value: T): void
  extern fn receive(): T?
  extern fn close(): void

// Errors
extern fn panic(message: string): never
  "Throws an unrecoverable error."
extern fn error(message: string, cause?: Error): Error
  "Creates an Error with optional cause."

// ============================================
// Pure Functions (implemented in Manuscript)
// ============================================

// Math helpers
fn abs(n: number): number
  "Returns the absolute value."
  if n < 0 then -n else n

fn min(a: number, b: number): number
  "Returns the smaller of two numbers."
  if a < b then a else b

fn max(a: number, b: number): number
  "Returns the larger of two numbers."
  if a > b then a else b

fn clamp(n: number, lo: number, hi: number): number
  "Constrains n to range [lo, hi]."
  min(max(n, lo), hi)

// Collection functions
fn first[T](list: list[T]): T?
  "Returns the first element, or null."
  if len(list) > 0 then list[0] else null

fn last[T](list: list[T]): T?
  "Returns the last element, or null."
  if len(list) > 0 then list[len(list) - 1] else null

fn take[T](list: list[T], n: number): list[T]
  "Returns the first n elements."
  let result = []
  for i in 0..min(n, len(list))
    result.push(list[i])
  result

fn drop[T](list: list[T], n: number): list[T]
  "Returns all but the first n elements."
  let result = []
  for i in n..len(list)
    result.push(list[i])
  result

fn reverse[T](list: list[T]): list[T]
  "Returns a reversed copy of the list."
  let result = []
  for i in 0..len(list)
    result.push(list[len(list) - 1 - i])
  result

fn contains[T](list: list[T], item: T): bool
  "Returns true if list contains item."
  for x in list
    if x == item
      return true
  false

fn unique[T](list: list[T]): list[T]
  "Returns list with duplicates removed."
  let seen = {}
  let result = []
  for item in list
    let key = to_str(item)
    if not seen[key]
      seen[key] = true
      result.push(item)
  result

fn flatten[T](lists: list[list[T]]): list[T]
  "Flattens a list of lists into one list."
  let result = []
  for list in lists
    for item in list
      result.push(item)
  result

fn zip[T, U](a: list[T], b: list[U]): list[list[any]]
  "Pairs elements from two lists."
  let result = []
  let n = min(len(a), len(b))
  for i in 0..n
    result.push([a[i], b[i]])
  result

fn concat[T](...lists: list[list[T]]): list[T]
  "Concatenates multiple lists into one."
  let result = []
  for list in lists
    for item in list
      result.push(item)
  result

fn range(start: number, end: number): list[number]
  "Returns list of integers [start, end)."
  let result = []
  for i in start..end
    result.push(i)
  result

fn slice[T](list: list[T], start: number, end?: number): list[T]
  "Returns a portion of the list."
  let e = end ?? len(list)
  let result = []
  for i in start..e
    result.push(list[i])
  result

// Higher-order functions
fn map[T, U](list: list[T], f: fn(T): U): list[U]
  "Transforms each element using f."
  let result = []
  for item in list
    result.push(f(item))
  result

fn each[T](list: list[T], f: fn(T): void): void
  "Calls f for each element."
  for item in list
    f(item)

fn filter[T](list: list[T], pred: fn(T): bool): list[T]
  "Keeps elements where pred returns true."
  let result = []
  for item in list
    if pred(item)
      result.push(item)
  result

fn reduce[T, U](list: list[T], init: U, f: fn(U, T): U): U
  "Folds list into a single value."
  var acc = init
  for item in list
    acc = f(acc, item)
  acc

fn find[T](list: list[T], pred: fn(T): bool): T?
  "Returns first element matching pred."
  for item in list
    if pred(item)
      return item
  null

fn any[T](list: list[T], pred: fn(T): bool): bool
  "Returns true if any element matches."
  for item in list
    if pred(item)
      return true
  false

fn all[T](list: list[T], pred: fn(T): bool): bool
  "Returns true if all elements match."
  for item in list
    if not pred(item)
      return false
  true

fn group_by[T, K](list: list[T], f: fn(T): K): map[K, list[T]]
  "Groups elements by key from f."
  var result = {}
  for item in list
    let key = f(item)
    if not result[key]
      result[key] = []
    result[key].push(item)
  result

fn sort_by[T, K](list: list[T], f: fn(T): K): list[T]
  "Sorts list by key from f."
  let pairs = map(list, (item) => [f(item), item])
  let sorted = sort(pairs)
  map(sorted, (pair) => pair[1] as T)

// String functions (extern - wrap JS string methods)
extern fn upper(s: string): string
  "Converts string to uppercase."
extern fn lower(s: string): string
  "Converts string to lowercase."
extern fn trim(s: string): string
  "Removes leading/trailing whitespace."
extern fn split(s: string, delim: string): list[string]
  "Splits string by delimiter."
extern fn join(list: list[string], delim: string): string
  "Joins strings with delimiter."
extern fn replace(s: string, old: string, replacement: string): string
  "Replaces occurrences of old with new."
extern fn starts_with(s: string, prefix: string): bool
  "Returns true if string starts with prefix."
extern fn ends_with(s: string, suffix: string): bool
  "Returns true if string ends with suffix."
extern fn substring(s: string, start: number, end?: number): string
  "Returns a portion of the string."
extern fn matches(s: string, pattern: string): bool
  "Returns true if string matches regex pattern."

// Set functions
fn set[T](list: list[T]): set[T]
  "Creates a set from a list."
  let result = {}
  for item in list
    result[item] = true
  result

fn union[T](a: set[T], b: set[T]): set[T]
  "Returns union of two sets."
  let result = {}
  for k in keys(a)
    result[k] = true
  for k in keys(b)
    result[k] = true
  result

fn intersect[T](a: set[T], b: set[T]): set[T]
  "Returns intersection of two sets."
  let result = {}
  for k in keys(a)
    if b[k]
      result[k] = true
  result

fn difference[T](a: set[T], b: set[T]): set[T]
  "Returns elements in a but not in b."
  let result = {}
  for k in keys(a)
    if not b[k]
      result[k] = true
  result

fn is_subset[T](a: set[T], b: set[T]): bool
  "Returns true if a is subset of b."
  for k in keys(a)
    if not b[k]
      return false
  true

// Result type
type Result[T, E]
  ok: bool
  value?: T
  error?: E

// Result helpers
fn ok[T](value: T): Result[T, never]
  "Creates a success Result."
  { ok: true, value: value }

fn err[E](error: E): Result[never, E]
  "Creates an error Result."
  { ok: false, error: error }

// Testing
fn assert(condition: bool, message?: string): void
  "Throws if condition is false."
  if not condition
    panic(message ?? "Assertion failed")

// Equality
fn equals[T](a: T, b: T): bool
  "Deep equality check using JSON."
  to_json(a) == to_json(b)
