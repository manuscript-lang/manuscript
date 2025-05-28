# Check Statement Tests
---

# Basic check statement
```ms
fn main() {
  let x = 10
  check x > 5, "x must be greater than 5"
}
```
```go
package main

import "errors"

func main() {
    x := 10
    if !(x > 5) {
        return nil, errors.New("x must be greater than 5")
    }
}
```

# Check statement with boolean variable
```ms
fn main() {
  let isValid = true
  check isValid, "validation failed"
}
```
```go
package main

import "errors"

func main() {
    isValid := true
    if !isValid {
        return nil, errors.New("validation failed")
    }
}
```

# Check statement with function call
```ms
fn isPositive(n number) bool {
  return n > 0
}

fn main() {
  let num = -5
  check isPositive(num), "number must be positive"
}
```
```go
package main

import "errors"

func isPositive(n number) bool {
    return n > 0
}
func main() {
    num := -5
    if !isPositive(num) {
        return nil, errors.New("number must be positive")
    }
}
```

# Check statement with complex condition
```ms
fn main() {
  let a = 10
  let b = 20
  check a < b && b > 15, "condition not met"
}
```
```go
package main

import "errors"

func main() {
    a := 10
    b := 20
    if !(a < b && b > 15) {
        return nil, errors.New("condition not met")
    }
}
```

# Multiple check statements
```ms
fn main() {
  let x = 5
  let y = 10
  check x > 0, "x must be positive"
  check y > x, "y must be greater than x"
  check x + y == 15, "sum must equal 15"
}
```
```go
package main

import "errors"

func main() {
    x := 5
    y := 10
    if !(x > 0) {
        return nil, errors.New("x must be positive")
    }
    if !(y > x) {
        return nil, errors.New("y must be greater than x")
    }
    if !(x+y == 15) {
        return nil, errors.New("sum must equal 15")
    }
}
```

# Check statement with string comparison
```ms
fn main() {
  let name = "Alice"
  check name != "", "name cannot be empty"
}
```
```go
package main

import "errors"

func main() {
    name := "Alice"
    if !(name != "") {
        return nil, errors.New("name cannot be empty")
    }
}
```

# Check statement with null check
```ms
fn main() {
  let data = null
  check data != null, "data cannot be null"
}
```
```go
package main

import "errors"

func main() {
    data := nil
    if !(data != nil) {
        return nil, errors.New("data cannot be null")
    }
}
```

# Check statement in function
```ms
fn validateAge(age number) {
  check age >= 0, "age cannot be negative"
  check age <= 150, "age cannot exceed 150"
}

fn main() {
  validateAge(25)
}
```
```go
package main

import "errors"

func validateAge(age number) {
    if !(age >= 0) {
        return nil, errors.New("age cannot be negative")
    }
    if !(age <= 150) {
        return nil, errors.New("age cannot exceed 150")
    }
}
func main() {
    validateAge(25)
}
```

# Check statement with array access
```ms
fn main() {
  let arr = [1, 2, 3]
  let index = 1
  check index >= 0 && index < 3, "index out of bounds"
  let value = arr[index]
}
```
```go
package main

import "errors"

func main() {
    arr := []interface{}{1, 2, 3}
    index := 1
    if !(index >= 0 && index < 3) {
        return nil, errors.New("index out of bounds")
    }
    value := arr[index]
}
```

# Check statement with parenthesized condition
```ms
fn main() {
  let x = 10
  let y = 5
  check (x > y), "x must be greater than y"
}
```
```go
package main

import "errors"

func main() {
    x := 10
    y := 5
    if !(x > y) {
        return nil, errors.New("x must be greater than y")
    }
}
``` 