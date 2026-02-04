// @test: With Syntax - let binding vs anonymous context

type Logger extends Context
  prefix: string
  
  fn init(prefix: string)
    super()
    prefix = prefix
  
  fn log(msg: string): string
    "{prefix}: {msg}"

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

// === Pattern 1: with let name = expr ===
// Use this when you need to access the context variable directly
with let myLogger = Logger("NAMED")
  // Can use myLogger directly in this block
  // @expect: NAMED: direct call
  print(myLogger.log("direct call"))
  // Functions with using also get access
  // @expect: NAMED: Hello, Alice
  print(greet("Alice"))

// === Pattern 2: with expr (anonymous) ===
// Use this when you only need to provide context for functions with 'using'
// The context is available to functions but not as a named variable
with Logger("ANON")
  // @expect: ANON: Hello, Bob
  print(greet("Bob"))

// === Multiple contexts - mixed patterns ===
type Config extends Context
  env: string
  
  fn init(env: string)
    super()
    env = env
  
  fn get_env(): string
    env

fn log_with_env(msg: string): string using (logger: Logger, config: Config)
  logger.log("[" + config.get_env() + "] " + msg)

// Both named
with let logger = Logger("APP"), let config = Config("prod")
  // @expect: APP: direct
  print(logger.log("direct"))
  // @expect: prod
  print(config.get_env())
  // @expect: APP: [prod] message
  print(log_with_env("message"))

// Named logger, anonymous config
with let logger = Logger("DEBUG"), Config("dev")
  // @expect: DEBUG: log
  print(logger.log("log"))
  // @expect: DEBUG: [dev] test
  print(log_with_env("test"))

// Both anonymous - just providing context for functions
with Logger("SILENT"), Config("staging")
  // @expect: SILENT: [staging] data
  print(log_with_env("data"))
