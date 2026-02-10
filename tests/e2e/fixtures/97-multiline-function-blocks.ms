// @test: Multiline function signatures and call arguments

fn add(
  a: number,
  b: number
): number
  a + b

// @expect: 3
print(add(1, 2))

fn wrap(
  x: number,
  y: number
): number
  add(x, y)

// @expect: 7
print(wrap(3, 4))

fn call_with_multiline(
  p: number,
  q: number
): number
  wrap(
    p,
    q
  )

// @expect: 11
print(call_with_multiline(5, 6))
