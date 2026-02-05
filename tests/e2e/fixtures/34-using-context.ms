// @test: Using Context - Dependency injection and context passing

// === Context types for dependency injection ===
// Logger context type (use with 'with')
context Logger
  prefix: string
  
  fn log(msg: string): string
    "{prefix}: {msg}"

// Mock logger for testing
context MockLogger
  fn log(msg: string): string
    "[MOCK] " + msg

// === Function uses context via 'using' ===
fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

// Instantiate context in with clause
with let prod_logger = Logger("PROD")
  // @expect: PROD: Hello, Alice
  print(greet("Alice"))

// Different mock logger
fn greetMock(name: string): string using (logger: MockLogger)
  logger.log("Hello, " + name)

with let mock_logger = MockLogger()
  // @expect: [MOCK] Hello, Bob
  print(greetMock("Bob"))

// Anonymous context (no variable needed)
with Logger("ANON")
  // @expect: ANON: Hello, Anonymous
  print(greet("Anonymous"))

// === Multiple context bindings ===
context Config
  env: string
  debug: bool
  
  fn get_env(): string
    env
  
  fn is_debug(): bool
    debug

fn process(data: string): string using (logger: Logger, config: Config)
  if config.is_debug()
    logger.log("[DEBUG] Processing: " + data)
  else
    logger.log("Processing: " + data)

// Multiple contexts in one with
with let logger = Logger("PROD"), let config = Config("dev", true)
  // @expect: PROD: [DEBUG] Processing: test-data
  print(process("test-data"))

with let logger = Logger("PROD"), let config = Config("prod", false)
  // @expect: PROD: Processing: live-data
  print(process("live-data"))

// === Nested with blocks ===
with let outer_logger = Logger("OUTER")
  // @expect: OUTER: Hello, outer message
  print(greet("outer message"))
  
  with let inner_logger = Logger("INNER")
    // @expect: INNER: Hello, inner
    print(greet("inner"))
  
  // Back to outer context
  // @expect: OUTER: Hello, back to outer
  print(greet("back to outer"))

// === Context with state ===
context Counter
  count: number = 0
  
  fn increment(): number
    count = count + 1
    count
  
  fn get_count(): number
    count

fn doWork(): number using (counter: Counter)
  counter.increment()

with let c = Counter()
  doWork()
  doWork()
  // @expect: 3
  print(c.increment())
  // @expect: 3
  print(c.get_count())

// === Environment pattern ===
context Env
  name: string
  version: number
  
  fn description(): string
    "{name} v{version}"

fn getEnvInfo(): string using (env: Env)
  "Running in: " + env.description()

with let e = Env("test", 1)
  // @expect: Running in: test v1
  print(getEnvInfo())

// === Settings pattern ===
context Settings
  maxRetries: number
  timeout: number
  
  fn getSettings(): map[string, number]
    {maxRetries: maxRetries, timeout: timeout}

fn configure(): map[string, number] using (s: Settings)
  s.getSettings()

with let settings = Settings(3, 5000)
  let cfg = configure()
  // @expect: 3
  print(cfg.maxRetries)
  // @expect: 5000
  print(cfg.timeout)
