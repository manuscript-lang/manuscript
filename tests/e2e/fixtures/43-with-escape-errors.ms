// @test: With Escape Errors - comprehensive escape and spawn restrictions
// @error: Cannot return closure that depends on context
// @error: Cannot use 'spawn' inside function-level 'with'

// === Setup ===

context Logger
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"
  fn close(): void

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

fn helper(): string using (logger: Logger)
  greet("from helper")

fn async_work(): number
  42

// Error 1: returning closure that captures with context (closure escapes)
fn escaping_closure(): fn (): string
  with let l = Logger(prefix: "ESCAPE")
    return () => greet("escaped")

// Allowed: spawn async_work() does not capture or use with context
fn spawn_in_with(): number
  with let l = Logger(prefix: "SPAWN")
    let handle = spawn async_work()
    let _ = race([handle])
    42

// Allowed: spawn greet("x") consumed with race() before block ends
fn spawn_context_dependent(): number
  with let l = Logger(prefix: "SPAWN")
    let handle = spawn greet("x")
    let _ = race([handle])
    42

// Error 2: spawn greet("x") not consumed before with block ends
fn spawn_context_escapes(): number
  with let l = Logger(prefix: "SPAWN")
    let handle = spawn greet("x")
    42

// Trigger type-check (both errors reported)
let f = escaping_closure()
let n = spawn_in_with()
let _ = spawn_context_dependent()
let _ = spawn_context_escapes()