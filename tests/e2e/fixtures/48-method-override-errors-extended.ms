// @test: Extended Method Override Errors - Return Type and Using Clause

// === Return type mismatch in override ===
type Base extends Context
  fn compute(x: number): number
    x * 2

type BadReturn extends Base
  fn compute(x: number): string
    "wrong"
// @error: returns

// === Parameter count mismatch in override ===
type Base2 extends Context
  fn process(a: number, b: number): number
    a + b

type BadParams extends Base2
  fn process(a: number): number
    a
// @error: different parameters

// === Using clause mismatch - adding requirements ===
type Logger extends Context
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"

type Base3 extends Context  
  fn action(): string
    "done"

type BadUsing extends Base3
  fn action(): string using (logger: Logger)
    logger.log("action")
// @error: different 'using' clause

// === Multiple override errors ===
type Handler extends Context
  fn handle(data: string): string
    data

type BadHandler extends Handler
  fn handle(data: number): number
    data
// @error: different parameters
