// @test: With in Functions - comprehensive valid patterns

// === Setup: Context types and using functions ===

type Logger extends Context
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"
  fn exit(): void
    print("{prefix}: cleanup")

type Counter extends Context
  count: number = 0
  fn inc(): number
    count = count + 1
    count

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

fn count_up(): number using (counter: Counter)
  counter.inc()

// === Basic Usage ===

fn test_direct_method()
  with let logger = Logger("DIRECT")
    // @expect: DIRECT: method call
    print(logger.log("method call"))

test_direct_method()
// @expect: DIRECT: cleanup

fn test_using_function()
  with let logger = Logger("USING")
    // @expect: USING: Hello, World
    print(greet("World"))

test_using_function()
// @expect: USING: cleanup

// === Closures (non-escaping) ===

fn test_immediate_closure()
  with let logger = Logger("IMM")
    let f = () => logger.log("from closure")
    // @expect: IMM: from closure
    print(f())

test_immediate_closure()
// @expect: IMM: cleanup

fn test_closure_calling_using()
  with let logger = Logger("CLSUSING")
    let f = (name: string) => greet(name)
    // @expect: CLSUSING: Hello, Bob
    print(f("Bob"))

test_closure_calling_using()
// @expect: CLSUSING: cleanup

fn test_stdlib_map()
  with let logger = Logger("MAP")
    let nums = [1, 2, 3]
    let results = map(nums, (n) => logger.log("{n}"))
    // @expect: [MAP: 1, MAP: 2, MAP: 3]
    print(results)

test_stdlib_map()
// @expect: MAP: cleanup

fn test_stdlib_each()
  with let logger = Logger("EACH")
    // @expect: EACH: item 1
    // @expect: EACH: item 2
    each([1, 2], (n) => print(logger.log("item {n}")))

test_stdlib_each()
// @expect: EACH: cleanup

// === Scope Patterns ===

fn test_loop_fresh_context()
  for i in [1, 2]
    with let logger = Logger("L{i}")
      // @expect: L1: iter
      // @expect: L1: cleanup
      // @expect: L2: iter
      // @expect: L2: cleanup
      print(logger.log("iter"))

test_loop_fresh_context()

fn test_nested_with()
  with let outer = Logger("OUT")
    // @expect: OUT: before inner
    print(outer.log("before inner"))
    with let inner = Logger("IN")
      // @expect: IN: inside
      print(inner.log("inside"))
    // @expect: IN: cleanup
    // @expect: OUT: after inner
    print(outer.log("after inner"))

test_nested_with()
// @expect: OUT: cleanup

fn test_sequential_with()
  with let first = Logger("1ST")
    // @expect: 1ST: first block
    print(first.log("first block"))
  // @expect: 1ST: cleanup
  with let second = Logger("2ND")
    // @expect: 2ND: second block
    print(second.log("second block"))

test_sequential_with()
// @expect: 2ND: cleanup

fn test_conditional_with(flag: bool)
  if flag
    with let logger = Logger("TRUE")
      // @expect: TRUE: branch taken
      print(logger.log("branch taken"))

test_conditional_with(true)
// @expect: TRUE: cleanup
test_conditional_with(false)

// === Return Patterns ===

fn make_pure_closure()
  with let logger = Logger("PURE")
    // @expect: PURE: setup
    print(logger.log("setup"))
    (n: number) => n * 2  // no context dependency - OK

let double = make_pure_closure()
// @expect: PURE: cleanup
// @expect: 10
print(double(5))

fn compute_value(): number
  with let counter = Counter()
    counter.inc()
    counter.inc()
    counter.count + 100  // return computed value

// @expect: 102
print(compute_value())

fn early_return_from_with(n: number): string
  with let logger = Logger("EARLY")
    if n < 0
      return "negative"
    logger.log("positive: {n}")

// @expect: EARLY: cleanup
// @expect: negative
print(early_return_from_with(-1))
// @expect: EARLY: cleanup
// @expect: EARLY: positive: 5
print(early_return_from_with(5))

// === Multiple Contexts ===

fn test_multiple_contexts()
  with let logger = Logger("MULTI"), let counter = Counter()
    // @expect: MULTI: count is 1
    print(logger.log("count is {counter.inc()}"))
    // @expect: MULTI: count is 2
    print(logger.log("count is {counter.inc()}"))

test_multiple_contexts()
// @expect: MULTI: cleanup

// === Control Flow Inside With ===

fn test_try_catch_in_with()
  with let logger = Logger("TRY")
    try
      // @expect: TRY: before error
      print(logger.log("before error"))
      throw "oops"
    catch e
      // @expect: TRY: caught oops
      print(logger.log("caught {e}"))

test_try_catch_in_with()
// @expect: TRY: cleanup

fn test_match_in_with(val: number): string
  with let logger = Logger("MATCH")
    match val
      1 => logger.log("one")
      2 => logger.log("two")
      _ => logger.log("other")

// @expect: MATCH: cleanup
// @expect: MATCH: one
print(test_match_in_with(1))
// @expect: MATCH: cleanup
// @expect: MATCH: two
print(test_match_in_with(2))
// @expect: MATCH: cleanup
// @expect: MATCH: other
print(test_match_in_with(99))

fn test_for_in_with()
  with let logger = Logger("FOR")
    for i in 1..4
      // @expect: FOR: i=1
      // @expect: FOR: i=2
      // @expect: FOR: i=3
      print(logger.log("i={i}"))

test_for_in_with()
// @expect: FOR: cleanup

// === Edge Cases ===

fn test_with_returns_context_value(): string
  with let logger = Logger("VAL")
    logger.prefix  // return context field value (not the context itself)

// @expect: VAL: cleanup
// @expect: VAL
print(test_with_returns_context_value())

fn test_chained_using()
  with let logger = Logger("CHAIN")
    // Call greet which uses logger, result used in another call
    let msg = greet("Chain")
    // @expect: CHAIN: result: CHAIN: Hello, Chain
    print(logger.log("result: {msg}"))

test_chained_using()
// @expect: CHAIN: cleanup

// === Spawn + Using + With: Valid Patterns ===

// Helper that does NOT need context
fn pure_compute(n: number): number
  n * 2

// Helper that provides its own context internally
fn self_contained_greet(name: string): string
  with let logger = Logger("SELF")
    greet(name)  // greet uses Logger, provided by internal with

// Spawn pure function, use with+using separately
fn test_spawn_pure_with_using()
  let task = spawn pure_compute(21)
  with let logger = Logger("PURE")
    // @expect: PURE: Hello, Pure
    print(greet("Pure"))  // greet uses Logger via using
  // @expect: PURE: cleanup
  race([task])
  // @expect: spawn pure done
  print("spawn pure done")

test_spawn_pure_with_using()

// Spawn function that has its own internal with
fn test_spawn_self_contained()
  // This works because the spawned function provides its own context
  let t1 = spawn self_contained_greet("Task1")
  let t2 = spawn self_contained_greet("Task2")
  race([t1, t2])
  // @expect: SELF: cleanup
  // @expect: SELF: cleanup
  // @expect: self contained done
  print("self contained done")

test_spawn_self_contained()

// Sequential: with block with using calls, then spawn pure work
fn test_using_then_spawn()
  with let logger = Logger("SEQ")
    // @expect: SEQ: Hello, First
    print(greet("First"))
    // @expect: SEQ: Hello, Second
    print(greet("Second"))
  // @expect: SEQ: cleanup
  // After with exits, spawn pure computation
  let task = spawn pure_compute(100)
  race([task])
  // @expect: using then spawn done
  print("using then spawn done")

test_using_then_spawn()

// Spawn before, then with+using, then consume
fn test_spawn_around_using()
  let task = spawn pure_compute(50)
  with let logger = Logger("AROUND")
    // Call function with using clause
    // @expect: AROUND: Hello, Middle
    print(greet("Middle"))
  // @expect: AROUND: cleanup
  race([task])
  // @expect: spawn around using done
  print("spawn around using done")

test_spawn_around_using()

// Multiple with blocks, spawn between them
fn test_multiple_with_spawn()
  with let logger = Logger("W1")
    // @expect: W1: Hello, One
    print(greet("One"))
  // @expect: W1: cleanup
  let task = spawn pure_compute(10)
  with let logger = Logger("W2")
    // @expect: W2: Hello, Two
    print(greet("Two"))
  // @expect: W2: cleanup
  race([task])
  // @expect: multiple with spawn done
  print("multiple with spawn done")

test_multiple_with_spawn()

// Nested using calls within with
fn outer_greet(name: string): string using (logger: Logger)
  "Outer: " + greet(name)  // calls greet which also uses Logger

fn test_nested_using_with_spawn()
  let task = spawn pure_compute(5)
  with let logger = Logger("NEST")
    // outer_greet calls greet, both use the same Logger
    // @expect: NEST: Outer: NEST: Hello, Nested
    print(logger.log(outer_greet("Nested")))
  // @expect: NEST: cleanup
  race([task])
  // @expect: nested using done
  print("nested using done")

test_nested_using_with_spawn()
