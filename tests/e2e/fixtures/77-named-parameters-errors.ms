// @test: Named Parameters Errors - mixed positional and named not allowed

fn triple(a: number, b: number, c: number): number
  a + b + c

// @error: Cannot mix positional and named arguments
let x = triple(10, c: 30, b: 20)

print(x)
