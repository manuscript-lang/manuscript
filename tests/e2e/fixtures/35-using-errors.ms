// @test: Using Context Errors - Types must extend Context
// @error: must extend Context

// This type does NOT extend Context - should cause error
type BadLogger
  prefix: string
  
  fn log(msg: string): string
    "{prefix}: {msg}"

// Using a non-Context type should fail
fn bad_greet(name: string): string using (logger: BadLogger)
  logger.log("Hello, " + name)
