// @test: Closable with - value before block, type with close(), error without close()

// === Type with close() used in with (not declared as context) ===
type MyResource
  name: string
  fn close(): void
    print(name + " closed")

with let r1 = MyResource(name: "R1")
  // @expect: R1
  print(r1.name)
// @expect: R1 closed

// === Value created before with block ===
let r2 = MyResource(name: "R2")
with r2
  // @expect: R2
  print(r2.name)
// @expect: R2 closed

// === Context type (has close()) still works ===
context Logger
  prefix: string
  fn log(msg: string): string
    "{prefix}: {msg}"
  fn close(): void
    return

with let log = Logger(prefix: "CLOSABLE")
  // @expect: CLOSABLE: ok
  print(log.log("ok"))
