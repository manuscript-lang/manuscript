// @test: Using Context - Dependency injection and context passing

// === Interface pattern: empty body functions define the contract ===
// ILogger is an interface - methods have signatures but no body
type ILogger extends Context
  fn log(msg: string): string

// Concrete implementation provides actual behavior
type ConsoleLogger extends ILogger
  prefix: string
  
  fn log(msg: string): string
    "{prefix}: {msg}"

// Another implementation - could be a mock for testing
type MockLogger extends ILogger
  fn log(msg: string): string
    "[MOCK] " + msg

// === Function uses the interface, not concrete type ===
fn greet(name: string): string using (logger: ILogger)
  logger.log("Hello, " + name)

// Instantiate context in with clause using 'with let name = expr'
with let prod_logger = ConsoleLogger("PROD")
  // @expect: PROD: Hello, Alice
  print(greet("Alice"))

// Swap to mock implementation - same function, different behavior
with let mock_logger = MockLogger()
  // @expect: [MOCK] Hello, Bob
  print(greet("Bob"))

// Anonymous context (no variable needed)
with ConsoleLogger("ANON")
  // @expect: ANON: Hello, Anonymous
  print(greet("Anonymous"))

// === Multiple context bindings ===
type IConfig extends Context
  fn get_env(): string
  fn is_debug(): bool

type AppConfig extends IConfig
  env: string
  debug: bool
  
  fn get_env(): string
    env
  
  fn is_debug(): bool
    debug

fn process(data: string): string using (logger: ILogger, config: IConfig)
  if config.is_debug()
    logger.log("[DEBUG] Processing: " + data)
  else
    logger.log("Processing: " + data)

// Multiple contexts in one with
with let logger = ConsoleLogger("PROD"), let config = AppConfig("dev", true)
  // @expect: PROD: [DEBUG] Processing: test-data
  print(process("test-data"))

with let logger = ConsoleLogger("PROD"), let config = AppConfig("prod", false)
  // @expect: PROD: Processing: prod-data
  print(process("prod-data"))

// === Swapping storage implementations ===
// Interface defines contract for storage
type IStorage extends Context
  fn save(key: string, value: string): string
  fn load(key: string): string

// In-memory implementation
type MemoryStorage extends IStorage
  name: string
  
  fn save(key: string, value: string): string
    "[{name}] Saved {key}={value}"
  
  fn load(key: string): string
    "[{name}] Loaded {key}"

// Functions use the interface, not concrete type
fn store_user(id: string, name: string): string using (storage: IStorage)
  storage.save("user:" + id, name)

fn get_user(id: string): string using (storage: IStorage)
  storage.load("user:" + id)

// Real storage
with let storage = MemoryStorage("RealDB")
  // @expect: [RealDB] Saved user:1=Alice
  print(store_user("1", "Alice"))
  // @expect: [RealDB] Loaded user:1
  print(get_user("1"))

// Mock storage for testing - same interface, different instance
with let storage = MemoryStorage("MockDB")
  // @expect: [MockDB] Saved user:2=Bob
  print(store_user("2", "Bob"))
  // @expect: [MockDB] Loaded user:2
  print(get_user("2"))

// === Nested function calls - using is NOT viral ===
// format_message needs ILogger, but send_notification does NOT need to declare using
fn format_message(msg: string): string using (logger: ILogger)
  logger.log(upper(msg))

// Note: NO using clause here! The context flows through automatically
fn send_notification(user: string, msg: string): string
  let formatted = format_message(msg)
  "Sent to " + user + ": " + formatted

with let logger = ConsoleLogger("NOTIF")
  // @expect: Sent to Bob: NOTIF: HELLO WORLD
  print(send_notification("Bob", "hello world"))

// === Context with computed values ===
type Counter extends Context
  count: number = 0
  
  fn increment(): number
    count = count + 1
    count
  
  fn get(): number
    count

fn track_operation(name: string): string using (counter: Counter)
  let n = counter.increment()
  "Operation {n}: " + name

with let tracker = Counter()
  // @expect: Operation 1: init
  print(track_operation("init"))
  // @expect: Operation 2: process
  print(track_operation("process"))
  // @expect: Operation 3: cleanup
  print(track_operation("cleanup"))
  // Verify counter state inside with block
  // @expect: 3
  print(tracker.get())

// === Context for different environments ===
type Env extends Context
  name: string
  base_url: string

fn make_request(path: string): string using (env: Env)
  env.base_url + path

with let env = Env("development", "http://localhost:8080")
  // @expect: http://localhost:8080/users
  print(make_request("/users"))

with let env = Env("production", "https://api.example.com")
  // @expect: https://api.example.com/users
  print(make_request("/users"))

// === Simple context ===
fn simple_log(msg: string): string using (logger: ILogger)
  logger.log(msg)

with let logger = ConsoleLogger("SIMPLE")
  // @expect: SIMPLE: test message
  print(simple_log("test message"))

// === Context with default values ===
type Settings extends Context
  theme: string = "light"
  language: string = "en"

fn get_theme(): string using (settings: Settings)
  settings.theme

fn get_language(): string using (settings: Settings)
  settings.language

with let settings = Settings()
  // @expect: light
  print(get_theme())
  // @expect: en
  print(get_language())

with let settings = Settings("dark", "es")
  // @expect: dark
  print(get_theme())
  // @expect: es
  print(get_language())

// === Chained context operations - non-viral ===
// Interface for formatters
type IFormatter extends Context
  fn format(s: string): string

// Concrete implementation
type BracketFormatter extends IFormatter
  fn format(s: string): string
    "[" + s + "]"

fn wrap(text: string): string using (formatter: IFormatter)
  formatter.format(text)

// double_wrap does NOT need using - it just calls wrap which will get context from runtime
fn double_wrap(text: string): string
  wrap(wrap(text))

with let fmt = BracketFormatter()
  // @expect: [[hello]]
  print(double_wrap("hello"))

// === Type-based matching ===
// The function uses 'logger: ILogger' but we provide ConsoleLogger
// Type matching works - ConsoleLogger implements ILogger
fn type_match_demo(): string using (logger: ILogger)
  logger.log("type matching works!")

with let myLog = ConsoleLogger("TYPE_MATCH")
  // myLog is ConsoleLogger which implements ILogger
  // @expect: TYPE_MATCH: type matching works!
  print(type_match_demo())
