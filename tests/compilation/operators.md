# Operator Compilation Tests
---

# Basic Arithmetic and Boolean Operators

```ms
let a = 10 + 5
let b = 10 - 5
let c = 10 * 5
let d = 10 / 5
let e = 10 % 3
let t = true
let f = false

let and1 = t && t
let and2 = t && f
let and3 = f && t
let and4 = f && f

let or1 = t || t
let or2 = t || f
let or3 = f || t
let or4 = f || f

let not1 = !t
let not2 = !f
```

```go
package main

func main() {
	a := 10 + 5
	b := 10 - 5
	c := 10 * 5
	d := 10 / 5
	e := 10 % 3
	t := true
	f := false
	and1 := t && t
	and2 := t && f
	and3 := f && t
	and4 := f && f
	or1 := t || t
	or2 := t || f
	or3 := f || t
	or4 := f || f
	not1 := !t
	not2 := !f
}
```

# Comparison Operators

```ms
let eq = 5 == 5
let neq = 5 != 10
let lt = 5 < 10
let gt = 10 > 5
let lte = 5 <= 5
let gte = 10 >= 10
```

```go
package main

func main() {
	eq := 5 == 5
	neq := 5 != 10
	lt := 5 < 10
	gt := 10 > 5
	lte := 5 <= 5
	gte := 10 >= 10
}
```

# Operator Precedence

```ms
let prec1 = true && false || true // (true && false) || true -> false || true -> true
let prec2 = true || false && true // true || (false && true) -> true || false -> true
let prec3 = (true || false) && false // true && false -> false
let prec4 = !(true && false) // !false -> true
```

```go
package main

func main() {
	prec1 := true && false || true
	prec2 := true || false && true
	prec3 := (true || false) && false
	prec4 := !(true && false)
}
```

# Assignment Operators

```ms
let x_add = 10
x_add += 5 // 15
let x_sub = 10
x_sub -= 5 // 5
let x_mul = 10
x_mul *= 5 // 50
let x_div = 10
x_div /= 5 // 2
let x_mod = 10
x_mod %= 3 // 1

let y_expr = 5
let x_add_expr = 10
x_add_expr += y_expr * 2 // 10 + 10 = 20
let x_sub_expr = 10
x_sub_expr -= y_expr * 2 // 10 - 10 = 0
let x_mul_expr = 10
x_mul_expr *= y_expr + 2 // 10 * 7 = 70
let x_div_expr = 20
x_div_expr /= y_expr - 1 // 20 / 4 = 5
let x_mod_expr = 20
x_mod_expr %= y_expr - 1 // 20 % 4 = 0

let x_xor = 12 // Binary 1100
x_xor ^= 5   // Binary 0101. Result: 9 (Binary 1001)
```

```go
package main

func main() {
	x_add := 10
	x_add = x_add + 5
	x_sub := 10
	x_sub = x_sub - 5
	x_mul := 10
	x_mul = x_mul * 5
	x_div := 10
	x_div = x_div / 5
	x_mod := 10
	x_mod = x_mod % 3
	y_expr := 5
	x_add_expr := 10
	x_add_expr = x_add_expr + y_expr*2
	x_sub_expr := 10
	x_sub_expr = x_sub_expr - y_expr*2
	x_mul_expr := 10
	x_mul_expr = x_mul_expr * (y_expr + 2)
	x_div_expr := 20
	x_div_expr = x_div_expr / (y_expr - 1)
	x_mod_expr := 20
	x_mod_expr = x_mod_expr % (y_expr - 1)
	x_xor := 12
	x_xor = x_xor ^ 5
}
```

# String Concatenation

```ms
let s1 = "hello"
let s2 = " world"
let str_res1 = s1 + s2
let str_res2 = "hello" + " " + "world"
let name_str = "User"
let str_res3 = "Hello, " + name_str + "!"
```

```go
package main

func main() {
	s1 := "hello"
	s2 := " world"
	str_res1 := s1 + s2
	str_res2 := "hello" + " " + "world"
	name_str := "User"
	str_res3 := "Hello, " + name_str + "!"
}
```

# Unary Operators

```ms
let x_un = 5
let y_neg = -x_un
let z_neg_lit = -10

let a_un = 10
let b_un = 3
let c_neg_expr = -(a_un - b_un)

let y_pos = +x_un
let z_pos_lit = +10
let c_pos_expr = +(a_un - b_un)
```
```go
package main

func main() {
	x_un := 5
	y_neg := -x_un
	z_neg_lit := -10
	a_un := 10
	b_un := 3
	c_neg_expr := -(a_un - b_un)
	y_pos := +x_un
	z_pos_lit := +10
	c_pos_expr := +(a_un - b_un)
}
```

# Chained Operator Tests

```ms
// Chained Arithmetic
let chain_add = 1 + 2 + 3 + 4 // Expected: ( ( (1+2) + 3) + 4 ) = 10
let chain_sub = 10 - 3 - 2 - 1 // Expected: ( ( (10-3) - 2) - 1 ) = 4
let chain_mul = 2 * 3 * 4 * 1 // Expected: ( ( (2*3) * 4) * 1 ) = 24
let chain_div = 24 / 2 / 3 / 2 // Expected: ( ( (24/2) / 3) / 2 ) = 2
let chain_mod = 27 % 10 % 4 % 3 // Expected: ( ( (27%10) % 4 ) % 3 ) = ( (7 % 4) % 3 ) = (3 % 3) = 0
let chain_mixed_arith = 1 + 2 * 3 - 4 / 2 // Expected: 1 + (2*3) - (4/2) = 1 + 6 - 2 = 5
let chain_mixed_arith2 = 10 - 2 * 3 + 8 / 4 % 3 // Expected: 10 - (2*3) + ( (8/4) % 3 ) = 10 - 6 + (2 % 3) = 10 - 6 + 2 = 6

// Chained Logical
let chain_and = true && true && false && true // Expected: false
let chain_or = false || false || true || false // Expected: true
let chain_and_or = true && false || true && true // Expected: (true && false) || (true && true) = false || true = true
let chain_or_and = true || true && false || false && true // Expected: true || (true && false) || (false && true) = true || false || false = true

// Chained String Concatenation (already covered but good to have one here)
let chain_str = "a" + "b" + "c" + "d"

// Chained Comparison
let chain_comp1 = 1 < 2 < 3 // Expected: (1 < 2) && (2 < 3) -> true && true -> true
let chain_comp2 = 10 > 5 > 1 // Expected: (10 > 5) && (5 > 1) -> true && true -> true
let chain_comp3 = 1 < 5 > 2 // Expected: (1 < 5) && (5 > 2) -> true && true -> true
let chain_comp4 = 1 == 1 == 1 // Expected: (1 == 1) && (1 == 1) -> true && true -> true
let chain_comp5 = 1 < 2 <= 2 < 3 // Expected: (1 < 2) && (2 <= 2) && (2 < 3) -> true && true && true -> true
let x_comp = 2
let chain_comp_var = 1 < x_comp < 3 // Expected: (1 < x_comp) && (x_comp < 3) -> (1 < 2) && (2 < 3) -> true
let chain_comp_mixed_ops = 1 < x_comp <= 5 > 3 == 3 // Expected: 1<2 && 2<=5 && 5>3 && 3==3 -> true
```

```go
package main

func main() {
	chain_add := 1 + 2 + 3 + 4
	chain_sub := 10 - 3 - 2 - 1
	chain_mul := 2 * 3 * 4 * 1
	chain_div := 24 / 2 / 3 / 2
	chain_mod := 27 % 10 % 4 % 3
	chain_mixed_arith := 1 + 2*3 - 4/2
	chain_mixed_arith2 := 10 - 2*3 + 8/4%3
	chain_and := true && true && false && true
	chain_or := false || false || true || false
	chain_and_or := true && false || true && true
	chain_or_and := true || true && false || false && true
	chain_str := "a" + "b" + "c" + "d"
	chain_comp1 := 1 < 2 && 2 < 3
	chain_comp2 := 10 > 5 && 5 > 1
	chain_comp3 := 1 < 5 && 5 > 2
	chain_comp4 := 1 == 1 && 1 == 1
	chain_comp5 := 1 < 2 && 2 <= 2 && 2 < 3
	x_comp := 2
	chain_comp_var := 1 < x_comp && x_comp < 3
	chain_comp_mixed_ops := (1 < x_comp && x_comp <= 5 && 5 > 3) == 3
}
```
