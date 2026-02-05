// @test: Multiline with clause - context can only be instantiated in with

context Logger
  prefix: string
  level: number = 0

  fn log(msg: string): string
    "{prefix}: {msg}"

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

// === Multiline with: call args on separate lines ===
with let l = Logger(
  prefix: "APP",
  level: 1
)
    // @expect: {"prefix":"APP","level":1}: direct
    print(l.log("direct"))
    // @expect: {"prefix":"APP","level":1}: Hello, World
    print(greet("World"))

// === Multiple contexts with newline between (multiline context list) ===
context Config
  env: string

fn getEnv(): string using (config: Config)
  config.env

fn logWithEnv(msg: string): string using (logger: Logger, config: Config)
  logger.log("[" + getEnv() + "] " + msg)

with Logger(prefix: "SVC"),
  let c = Config(env: "prod")
    // @expect: {"prefix":"SVC"}: [[object Object]] started
    print(logWithEnv("started"))
