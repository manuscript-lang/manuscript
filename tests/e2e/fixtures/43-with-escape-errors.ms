// @test: With Escape Errors - comprehensive escape and spawn restrictions
// @error: Cannot return closure that depends on context
// @error: Cannot use 'spawn' inside function-level 'with'

// === Setup ===

type Logger extends Context
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

fn helper(): string using (logger: Logger)
  greet("from helper")

fn async_work(): number
  42

// ============================================
// CLOSURE ESCAPE ERRORS
// ============================================

// === Direct escape: closure calls using function ===
fn escape_direct()
  with let logger = Logger("X")
    () => greet("test")

// === Transitive escape: closure calls fn that uses context ===
fn escape_transitive()
  with let logger = Logger("X")
    () => helper()

// === Escape from nested with (inner closure escapes outer) ===
fn escape_nested_with()
  with let outer = Logger("OUT")
    with let inner = Logger("IN")
      () => greet("nested")

// === Escape via explicit return ===
fn escape_explicit_return()
  with let logger = Logger("X")
    return () => greet("explicit")

// ============================================
// SPAWN INSIDE WITH ERRORS
// ============================================

// === Basic spawn in with ===
fn spawn_in_with()
  with let logger = Logger("X")
    spawn async_work()

// === Spawn in if inside with ===
fn spawn_in_if_in_with(flag: bool)
  with let logger = Logger("X")
    if flag
      spawn async_work()

// === Spawn in for loop inside with ===
fn spawn_in_for_in_with()
  with let logger = Logger("X")
    for i in [1, 2]
      spawn async_work()

// === Spawn in nested with ===
fn spawn_in_nested_with()
  with let outer = Logger("OUT")
    with let inner = Logger("IN")
      spawn async_work()

// === Spawn in try inside with ===
fn spawn_in_try_in_with()
  with let logger = Logger("X")
    try
      spawn async_work()
    catch e
      print(e)

// === Spawn in match inside with ===
fn spawn_in_match_in_with(n: number)
  with let logger = Logger("X")
    match n
      1 => spawn async_work()
      _ => spawn async_work()

// All functions above should fail to compile
// Test passes if all expected errors are found
