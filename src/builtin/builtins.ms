// ============================================
// Manuscript Builtins
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
  fn upper(): string
  fn lower(): string
  fn trim(): string
  fn split(sep: string): list[string]
  fn contains(s: string): bool
  fn starts_with(prefix: string): bool
  fn ends_with(suffix: string): bool
  fn replace(old: string, new: string): string
  fn slice(start: number, end?: number): string
  fn char_at(index: number): string?
  fn index_of(s: string): number?
  fn repeat(n: number): string
  fn pad_start(len: number, char?: string): string
  fn pad_end(len: number, char?: string): string
  fn chars(): list[string]

extern type list[T]
  length: number
  fn push(item: T): list[T]
  fn pop(): T?
  fn shift(): T?
  fn contains(item: T): bool
  fn index_of(item: T): number?
  fn join(sep?: string): string
  fn reverse(): list[T]
  fn slice(start: number, end?: number): list[T]
  fn map[U](f: fn(T): U): list[U]
  fn filter(f: fn(T): bool): list[T]
  fn reduce[U](f: fn(U, T): U, init: U): U
  fn find(f: fn(T): bool): T?
  fn every(f: fn(T): bool): bool
  fn some(f: fn(T): bool): bool
  fn first(): T?
  fn last(): T?
  fn is_empty(): bool
  fn sort(cmp?: fn(T, T): number): list[T]

extern type map[K, V]
  size: number
  fn get(key: K): V?
  fn set(key: K, value: V): void
  fn has(key: K): bool
  fn delete(key: K): bool
  fn keys(): list[K]
  fn values(): list[V]
  fn entries(): list[list[unknown]]
  fn clear(): void

extern type set[T]
  size: number
  fn add(item: T): set[T]
  fn has(item: T): bool
  fn delete(item: T): bool
  fn clear(): void
  fn values(): list[T]
  fn entries(): list[list[T]]
  fn keys(): list[T]
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
// Async Types
// ============================================

extern type Promise[T]
extern type Stream[T]

// ============================================
// Intrinsic Functions
// ============================================

// I/O
extern fn print(...args: unknown): void
extern fn log(...args: unknown): void

// Type operations
extern fn typeof[T](x: T): string
extern fn clone[T](x: T): T
extern fn hash[T](x: T): number

// Conversion
extern fn to_str[T](x: T): string
extern fn to_num(s: string): number
extern fn getenv(name: string): string
extern fn to_json[T](x: T): string
extern fn from_json[T](s: string): T

// Time
extern fn now(): number

// Collections
extern fn len[T](x: T): number

// Errors
extern fn panic(message: string): never
extern fn error(message: string, cause?: Error): Error

// String functions
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

// Set functions
extern fn set[T](list: list[T]): set[T]
extern fn union[T](a: set[T], b: set[T]): set[T]
extern fn intersect[T](a: set[T], b: set[T]): set[T]
extern fn difference[T](a: set[T], b: set[T]): set[T]
extern fn is_subset[T](a: set[T], b: set[T]): bool

// ============================================
// Pure Functions
// ============================================

// Result type for error handling
type Result[T, E]
  ok: bool
  value?: T
  error?: E

fn ok[T](value: T): Result[T, never]
  Result(ok: true, value: value)

fn err[E](error: E): Result[never, E]
  Result(ok: false, error: error)

fn assert(condition: bool, message?: string): void
  if not condition
    panic(message ?? "Assertion failed")

fn equals[T](a: T, b: T): bool
  to_json(a) == to_json(b)
