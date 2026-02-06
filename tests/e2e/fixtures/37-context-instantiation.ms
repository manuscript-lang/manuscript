// @test: Context instantiation allowed outside with (Closable)

type Logger
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"
  fn close(): void
    return

let logger = Logger(prefix: "OK")
// @expect: OK: works outside with
print(logger.log("works outside with"))
