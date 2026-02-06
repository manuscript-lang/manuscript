// @test: Multiline with clause - context can only be instantiated in with

type Logger
  prefix: string
  level: number = 0

  fn log(msg: string): string
    "{prefix}: {msg}"
  fn close(): void
    return

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

// === Multiline with: call args on separate lines ===
with let l = Logger(
  prefix: "APP",
  level: 1
)
    // @expect: APP: direct
    print(l.log("direct"))
    // @expect: APP: Hello, World
    print(greet("World"))

// === Multiple contexts with newline between (multiline context list) ===
type Config
  env: string
  fn close(): void
    return

fn getEnv(): string using (config: Config)
  config.env

fn logWithEnv(msg: string): string using (logger: Logger, config: Config)
  logger.log("[" + getEnv() + "] " + msg)

with Logger(prefix: "SVC"),
  let c = Config(env: "prod")
    // @expect: SVC: [prod] started
    print(logWithEnv("started"))
