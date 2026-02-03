// @test: Context/Using Edge Cases - Capability system stress test

// === Basic context passing ===
type Logger extends Context
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

with let l = Logger("[INFO]")
  // @expect: [INFO]: Hello, World
  print(greet("World"))

// === Transitive context propagation ===
fn inner_fn(): string using (logger: Logger)
  logger.log("inner")

fn middle_fn(): string using (logger: Logger)
  inner_fn()

fn outer_fn(): string using (logger: Logger)
  middle_fn()

with let l2 = Logger("[TRACE]")
  // @expect: [TRACE]: inner
  print(outer_fn())

// === Multiple contexts ===
type Counter extends Context
  count: number = 0
  fn increment(): number
    count = count + 1
    count

fn use_both(): string using (logger: Logger, counter: Counter)
  let n = counter.increment()
  logger.log("count is {n}")

with let log = Logger("[COUNT]")
  with let cnt = Counter()
    // @expect: [COUNT]: count is 1
    print(use_both())
    // @expect: [COUNT]: count is 2
    print(use_both())

// === Context in loops ===
fn log_items(items: list[string]) using (logger: Logger)
  for item in items
    print(logger.log(item))

with let log4 = Logger("[ITEM]")
  // @expect: [ITEM]: a
  // @expect: [ITEM]: b
  // @expect: [ITEM]: c
  log_items(["a", "b", "c"])

// === Context in match expressions ===
fn process_value(v: number): string using (logger: Logger)
  match v
    0 => logger.log("zero")
    1 => logger.log("one")
    _ => logger.log("other")

with let log5 = Logger("[MATCH]")
  // @expect: [MATCH]: zero
  print(process_value(0))
  // @expect: [MATCH]: one
  print(process_value(1))
  // @expect: [MATCH]: other
  print(process_value(42))

// === Context in try/catch ===
fn risky_op(): string using (logger: Logger)
  try
    throw("oops")
  catch e
    return logger.log("caught: {e}")
  "unreachable"

with let log6 = Logger("[ERR]")
  // @expect: [ERR]: caught: oops
  print(risky_op())

// === Nested with blocks with same context type ===
with let outer = Logger("[OUTER]")
  // @expect: [OUTER]: Hello, outside
  print(greet("outside"))
  with let inner = Logger("[INNER]")
    // @expect: [INNER]: Hello, inside
    print(greet("inside"))
  // @expect: [OUTER]: Hello, back
  print(greet("back"))

// === Context with default values ===
type AppConfig extends Context
  debug: bool = false
  verbose: bool = true

fn should_log(): bool using (config: AppConfig)
  config.debug or config.verbose

with let cfg = AppConfig()
  // @expect: true
  print(should_log())

with let cfg2 = AppConfig(true, false)
  // @expect: true
  print(should_log())
