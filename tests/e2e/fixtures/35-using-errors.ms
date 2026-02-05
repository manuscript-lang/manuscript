// @test: Using Context Errors - Types must satisfy Closable
// @error: must satisfy Closable

// This type does NOT embed Context - should cause error
type BadLogger
  prefix: string
  
  fn log(msg: string): string
    "{prefix}: {msg}"

// Using a non-Context type should fail
fn bad_greet(name: string): string using (logger: BadLogger)
  logger.log("Hello, " + name)
