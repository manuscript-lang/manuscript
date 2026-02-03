// @test: With Runtime Errors - context not available at runtime
// @error: No context of type 'Logger' available

type Logger extends Context
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"

fn greet(name: string): string using (logger: Logger)
  logger.log("Hello, " + name)

// Calling a using function without providing context via with
// This compiles but fails at runtime
fn call_without_context()
  greet("test")

call_without_context()
