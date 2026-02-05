// @test: Set literals

let a: set[number] = <1, 2, 3>
// @expect: 3
print(len(a))
// @expect: true
print(a.has(1))
// @expect: true
print(a.has(2))
// @expect: false
print(a.has(4))

let b = <>
// @expect: 0
print(len(b))
// @expect: false
print(b.has(1))

let c = <"x", "y">
// @expect: 2
print(len(c))
// @expect: true
print(c.has("x"))

for x in a
  print(x)
// @expect: 1
// @expect: 2
// @expect: 3
