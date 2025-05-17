### Test Cases for Data Types

#### Integer Literals

```ms
fn main() {
  // Positive Integer
  let a = 123

  // Negative Integer
  let b = -456

  // Zero
  let c = 0

  // Large Integer
  let d = 9876543210

  // Integer assigned from an expression
  let e = 10 + 20
  let f = 100 - 50
}
```

```go
package main

func main() {
	a := 123
	b := -456
	c := 0
	d := 9876543210
	e := 10 + 20
	f := 100 - 50
}
```

#### Floating-Point Literals

```ms
fn main() {
  let fa = 1.23 // Positive float
  let fb = -0.005 // Negative float
  let fc = 0.0 // Zero float
  let fd = .5 // Float without leading zero
  // Float assigned from an expression
  let fe = 0.5 + 1.2
  let ff = 10.0 / 4.0
}
```

```go
package main

func main() {
	fa := 1.23
	fb := -0.005
	fc := 0.0
	fd := .5
	fe := 0.5 + 1.2
	ff := 10.0 / 4.0
}
```

#### Boolean Literals and Assignment

```ms
fn main() {
  let ba = true
  let bb = false
  let be = 10 > 5
  let bf = 10 == 10
  let bg = 10 < 5
}
```

```go
package main

func main() {
	ba := true
	bb := false
	be := 10 > 5
	bf := 10 == 10
	bg := 10 < 5
}
```

#### Null Literal

```ms
fn main() {
  let na = null
}
```

```go
package main

func main() {
	na := nil
}
``` 