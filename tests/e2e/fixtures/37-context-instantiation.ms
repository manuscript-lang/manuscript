// @test: Context Instantiation Restriction - only in with clauses
// @error: can only be instantiated in 'with' clauses

type Logger extends Context
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"

// ERROR: Context type instantiated outside of 'with'
let logger = Logger("BAD")

print(logger.log("this should fail"))
