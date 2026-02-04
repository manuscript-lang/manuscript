// @test: Escape Analysis - Context safety
// @error: no init block
// @error: only be instantiated in 'with'

// === Context Type Definition ===

type Logger extends Context
  prefix: string
  
  fn log(msg: string): void
    print(prefix + ": " + msg)

// === Valid Context Usage ===

fn with_context(): void
  with let log = Logger("APP")
    log.log("hello")

// === Nested With Blocks ===

fn nested_contexts(): void
  with let outer = Logger("OUT")
    with let inner = Logger("IN")
      outer.log("outer")
      inner.log("inner")

// === Context in Loops ===

fn loop_with_context(): void
  with let log = Logger("LOOP")
    for i in [1, 2, 3]
      log.log(to_str(i))

// === Context in Match ===

fn match_with_context(x: number): void
  with let log = Logger("MATCH")
    match x
      0 => log.log("zero")
      _ => log.log("other")

// === Context Instantiation Outside With ===

fn bad_instantiation(): Logger
  Logger("BAD")
