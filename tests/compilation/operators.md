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