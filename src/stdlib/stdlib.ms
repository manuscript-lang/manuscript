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
extern fn log(...args: any): void

// Math (require JS Math object)
extern fn sqrt(n: number): number
extern fn pow(base: number, exp: number): number
extern fn floor(n: number): number
extern fn ceil(n: number): number
extern fn round(n: number): number
extern fn random(): number
extern fn random_int(min: number, max: number): number

// Type operations
extern fn typeof[T](x: T): string
extern fn clone[T](x: T): T
extern fn hash[T](x: T): number

// Conversion
extern fn to_str[T](x: T): string
extern fn to_num(s: string): number
extern fn to_json[T](x: T): string
extern fn from_json[T](s: string): T

// Time
extern fn now(): number
extern fn sleep(ms: number): void

// Collections (need JS runtime)
extern fn len[T](x: T): number
extern fn keys[K, V](m: map[K, V]): list[K]
extern fn values[K, V](m: map[K, V]): list[V]
extern fn entries[K, V](m: map[K, V]): list[list[any]]
extern fn sort[T](list: list[T]): list[T]

// Concurrency (spawn is a keyword, not a function - type checked internally)
// race accepts heterogeneous promises (e.g., data fetch vs timeout)
extern fn race(promises: list[promise[any]]): promise[any]
extern fn timeout[T](ms: number, promise: promise[T]): promise[T]
extern fn delay(ms: number): promise[void]

// Channels - Channel[T] is a type with extern methods
type Channel[T]
  buffer?: number
  extern fn send(value: T): void
  extern fn receive(): T?
  extern fn close(): void

// Errors
extern fn panic(message: string): never
extern fn error(message: string, cause?: Error): Error

// ============================================
// Pure Functions (implemented in Manuscript)
// ============================================

// Math helpers
fn abs(n: number): number
  if n < 0 then -n else n

fn min(a: number, b: number): number
  if a < b then a else b

fn max(a: number, b: number): number
  if a > b then a else b

fn clamp(n: number, lo: number, hi: number): number
  min(max(n, lo), hi)

// Collection functions
fn first[T](list: list[T]): T?
  if len(list) > 0 then list[0] else null

fn last[T](list: list[T]): T?
  if len(list) > 0 then list[len(list) - 1] else null

fn take[T](list: list[T], n: number): list[T]
  let result = []
  for i in 0..min(n, len(list))
    result.push(list[i])
  result

fn drop[T](list: list[T], n: number): list[T]
  let result = []
  for i in n..len(list)
    result.push(list[i])
  result

fn reverse[T](list: list[T]): list[T]
  let result = []
  for i in 0..len(list)
    result.push(list[len(list) - 1 - i])
  result

fn contains[T](list: list[T], item: T): bool
  for x in list
    if x == item
      return true
  false

fn unique[T](list: list[T]): list[T]
  let seen = {}
  let result = []
  for item in list
    let key = to_str(item)
    if not seen[key]
      seen[key] = true
      result.push(item)
  result

fn flatten[T](lists: list[list[T]]): list[T]
  let result = []
  for list in lists
    for item in list
      result.push(item)
  result

fn zip[T, U](a: list[T], b: list[U]): list[list[any]]
  let result = []
  let n = min(len(a), len(b))
  for i in 0..n
    result.push([a[i], b[i]])
  result

fn concat[T](...lists: list[list[T]]): list[T]
  let result = []
  for list in lists
    for item in list
      result.push(item)
  result

fn range(start: number, end: number): list[number]
  let result = []
  for i in start..end
    result.push(i)
  result

fn slice[T](list: list[T], start: number, end?: number): list[T]
  let e = end ?? len(list)
  let result = []
  for i in start..e
    result.push(list[i])
  result

// Higher-order functions
fn map[T, U](list: list[T], f: fn(T): U): list[U]
  let result = []
  for item in list
    result.push(f(item))
  result

fn each[T](list: list[T], f: fn(T): void): void
  for item in list
    f(item)

fn filter[T](list: list[T], pred: fn(T): bool): list[T]
  let result = []
  for item in list
    if pred(item)
      result.push(item)
  result

fn reduce[T, U](list: list[T], init: U, f: fn(U, T): U): U
  var acc = init
  for item in list
    acc = f(acc, item)
  acc

fn find[T](list: list[T], pred: fn(T): bool): T?
  for item in list
    if pred(item)
      return item
  null

fn any[T](list: list[T], pred: fn(T): bool): bool
  for item in list
    if pred(item)
      return true
  false

fn all[T](list: list[T], pred: fn(T): bool): bool
  for item in list
    if not pred(item)
      return false
  true

fn group_by[T, K](list: list[T], f: fn(T): K): map[K, list[T]]
  var result = {}
  for item in list
    let key = f(item)
    if not result[key]
      result[key] = []
    result[key].push(item)
  result

fn sort_by[T, K](list: list[T], f: fn(T): K): list[T]
  let pairs = map(list, (item) => [f(item), item])
  let sorted = sort(pairs)
  map(sorted, (pair) => pair[1] as T)

// String functions (extern - wrap JS string methods)
extern fn upper(s: string): string
extern fn lower(s: string): string
extern fn trim(s: string): string
extern fn split(s: string, delim: string): list[string]
extern fn join(list: list[string], delim: string): string
extern fn replace(s: string, old: string, replacement: string): string
extern fn starts_with(s: string, prefix: string): bool
extern fn ends_with(s: string, suffix: string): bool
extern fn substring(s: string, start: number, end?: number): string
extern fn matches(s: string, pattern: string): bool

// Set functions (using maps as sets)
fn set[T](list: list[T]): set[T]
  let result = {}
  for item in list
    result[item] = true
  result

fn union[T](a: set[T], b: set[T]): set[T]
  let result = {}
  for k in keys(a)
    result[k] = true
  for k in keys(b)
    result[k] = true
  result

fn intersect[T](a: set[T], b: set[T]): set[T]
  let result = {}
  for k in keys(a)
    if b[k]
      result[k] = true
  result

fn difference[T](a: set[T], b: set[T]): set[T]
  let result = {}
  for k in keys(a)
    if not b[k]
      result[k] = true
  result

fn is_subset[T](a: set[T], b: set[T]): bool
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
  { ok: true, value: value }

fn err[E](error: E): Result[never, E]
  { ok: false, error: error }

// Testing
fn assert(condition: bool, message?: string): void
  if not condition
    panic(message ?? "Assertion failed")

// Equality
fn equals[T](a: T, b: T): bool
  to_json(a) == to_json(b)
