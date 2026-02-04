// @test: With Syntax - let binding vs anonymous context

type Logger
  Context
  prefix: string
  
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
  
  // Also available via using
  // @expect: NAMED: Hello, Alice
  print(greet("Alice"))

// === Pattern 2: with expr (anonymous) ===
// Use this when you only need the context for 'using' functions
with Logger("ANON")
  // Context is available for using functions
  // @expect: ANON: Hello, Bob
  print(greet("Bob"))

// === Both patterns in sequence ===
with let outer = Logger("OUTER")
  // @expect: OUTER: Hello, Outer
  print(greet("Outer"))
  
with Logger("INNER")
  // @expect: INNER: Hello, Inner
  print(greet("Inner"))

// === Two-argument config type ===
type Config
  Context
  env: string
  debug: bool

fn getEnv(): string using (config: Config)
  config.env

// Positional arguments
with let c = Config("production", false)
  // @expect: production
  print(getEnv())
