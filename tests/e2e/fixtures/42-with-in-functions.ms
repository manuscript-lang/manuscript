// @test: With in Functions - comprehensive valid patterns

// === Setup: Context types and using functions ===

type Logger
  Context
  prefix: string
  
  fn log(msg: string): string
    "{prefix}: {msg}"
  fn exit(): void
    print("{prefix}: cleanup")

type Counter
  Context
  count: number = 0
  
  fn increment(): number
    count = count + 1
    count
  fn get(): number
    count

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

fn countOps(): number using (counter: Counter)
  counter.increment()

// === Pattern 1: Simple with at function start ===
fn simpleWith(): string
  with let l = Logger("FUNC")
    greet("World")

// @expect: FUNC: cleanup
// @expect: FUNC: Hello, World
print(simpleWith())

// === Pattern 2: Multiple with blocks in sequence ===
fn multipleWith(): number
  var total = 0
  with let c1 = Counter()
    total = countOps()
    total = countOps()
  with let c2 = Counter(10)
    total = total + countOps()
  total

// @expect: 13
print(multipleWith())

// === Pattern 3: Nested with blocks ===
fn nestedWith(): string
  with let outer = Logger("OUTER")
    let msg1 = greet("First")
    with let inner = Logger("INNER")
      let msg2 = greet("Second")
      msg1 + " | " + msg2

// @expect: INNER: cleanup
// @expect: OUTER: cleanup
// @expect: OUTER: Hello, First | INNER: Hello, Second
print(nestedWith())

// === Pattern 4: With in conditional branches ===
fn conditionalWith(useFirst: bool): string
  if useFirst
    with let l = Logger("FIRST")
      greet("A")
  else
    with let l = Logger("SECOND")
      greet("B")

// @expect: FIRST: cleanup
// @expect: FIRST: Hello, A
print(conditionalWith(true))
// @expect: SECOND: cleanup
// @expect: SECOND: Hello, B
print(conditionalWith(false))

// === Pattern 5: With in loop ===
fn withInLoop(): number
  var sum = 0
  for i in [1, 2, 3]
    with let c = Counter(i * 10)
      sum = sum + countOps()
  sum

// @expect: 63
print(withInLoop())

// === Pattern 6: Multiple contexts in one with ===
fn multiContext(): string
  with let l = Logger("MULTI"), let c = Counter()
    let n = countOps()
    l.log("count is " + to_str(n))

// @expect: MULTI: cleanup
// @expect: MULTI: count is 1
print(multiContext())

// === Pattern 7: With with early return ===
fn withEarlyReturn(val: number): string
  with let l = Logger("EARLY")
    if val < 0
      return l.log("negative")
    l.log("positive: " + to_str(val))

// @expect: EARLY: cleanup
// @expect: EARLY: negative
print(withEarlyReturn(-5))
// @expect: EARLY: cleanup
// @expect: EARLY: positive: 10
print(withEarlyReturn(10))
