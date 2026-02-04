// @test: Context/Using Edge Cases - Capability system stress test

// === Basic context passing ===
type Logger
  Context
  prefix: string
  
  fn log(msg: string): string
    "{prefix}: {msg}"

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

with let l = Logger("[INFO]")
  // @expect: [INFO]: Hello, World
  print(greet("World"))

// === Nested contexts of same type ===
type Counter
  Context
  name: string
  value: number = 0
  
  fn increment(): number
    value = value + 1
    value
  
  fn getName(): string
    name

fn countOp(): number using (counter: Counter)
  counter.increment()

fn getCounterName(): string using (counter: Counter)
  counter.getName()

with let outer = Counter("outer", 0)
  // @expect: 1
  print(countOp())
  
  with let inner = Counter("inner", 100)
    // Inner shadows outer
    // @expect: 101
    print(countOp())
    // @expect: inner
    print(getCounterName())
  
  // Back to outer
  // @expect: 2
  print(countOp())
  // @expect: outer
  print(getCounterName())

// === Context with state modifications ===
type Accumulator
  Context
  total: number = 0
  
  fn add(n: number): number
    total = total + n
    total
  
  fn getTotal(): number
    total

fn addValue(n: number): number using (acc: Accumulator)
  acc.add(n)

fn readTotal(): number using (acc: Accumulator)
  acc.getTotal()

with let acc = Accumulator()
  addValue(10)
  addValue(20)
  addValue(5)
  // @expect: 35
  print(readTotal())

// === Multiple independent contexts ===
type Config
  Context
  env: string
  
  fn getEnv(): string
    env

fn getEnvironment(): string using (config: Config)
  config.getEnv()

fn logWithEnv(msg: string): string using (logger: Logger, config: Config)
  logger.log("[" + config.getEnv() + "] " + msg)

with let l = Logger("APP"), let c = Config("prod")
  // @expect: APP: [prod] system started
  print(logWithEnv("system started"))

// === Context method with mutable state ===
type Builder
  Context
  parts: number = 0
  result: string = ""
  
  fn add(part: string): void
    if parts == 0
      result = part
    else
      result = result + "-" + part
    parts = parts + 1
  
  fn build(): string
    result

fn addPart(part: string) using (builder: Builder)
  builder.add(part)

with let b = Builder()
  addPart("hello")
  addPart("world")
  addPart("foo")
  // @expect: hello-world-foo
  print(b.build())

// === Conditional context usage ===
type Feature
  Context
  enabled: bool
  
  fn isEnabled(): bool
    enabled

fn checkFeature(): bool using (feature: Feature)
  feature.isEnabled()

fn maybeLog(msg: string): string using (logger: Logger, feature: Feature)
  if feature.isEnabled()
    logger.log(msg)
  else
    "[disabled]"

with let l = Logger("LOG"), let f = Feature(true)
  // @expect: LOG: feature enabled
  print(maybeLog("feature enabled"))

with let l = Logger("LOG"), let f = Feature(false)
  // @expect: [disabled]
  print(maybeLog("feature disabled"))
