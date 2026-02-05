// @test: With Escape Errors - comprehensive escape and spawn restrictions
// @error: Cannot return closure that depends on context
// @error: Cannot use 'spawn' inside function-level 'with'

// === Setup ===

context Logger
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

fn helper(): string using (logger: Logger)
  greet("from helper")

fn async_work(): number
  42


// === Error 1: Returning closure that captures context ===
fn escaping_closure(): fn (): string
  with let l = Logger(prefix: "ESCAPE")
    // ERROR: This closure captures the context and escapes the with block
    return () => greet("escaped")

// === Error 2: Spawn inside function-level with ===
fn spawn_in_with(): number
  with let l = Logger(prefix: "SPAWN")
    // ERROR: Spawn would escape the with block's lifetime
    let handle = spawn async_work()
    // The with block ends here but the spawn might still be running
    42

// Call to trigger the errors
let f = escaping_closure()
let n = spawn_in_with()
