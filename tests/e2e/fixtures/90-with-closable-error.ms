// @test: With requires Closable - error when type has no close()
// @error: must satisfy Closable

type NoClose
  x: number
  fn get(): number
    x

with let n = NoClose(x: 1)
  print(n.get())
