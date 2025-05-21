# Expression Compilation Tests
---

# Parenthesized Expressions

```ms
fn main() {
    let a = (5 + 3)
    let b = (a * 2)
    let c = ((5 + 3) * 2)
    let d = (5 + (3 * 2))
    let e = ((5 + 3) * (2 + 1))
    let f = (((2 + 2) * (3 - 1)) + ((10 / 2) - 1))
}
```

```go
package main

func main() {
    a := 5 + 3
    b := a * 2
    c := (5 + 3) * 2
    d := 5 + 3*2
    e := (5 + 3) * (2 + 1)
    f := (2+2)*(3-1) + (10/2 - 1)
}
```

# Nested Expressions

```ms
fn main() {
    let a = 5
    let b = 3
    let c = a + b * 2
    let d = (a + b) * 2
    let e = a + b / 2
    let f = (a + b) / 2
    let g = a * b + a / b
    let h = a * (b + a) / b
}
```

```go
package main

func main() {
    a := 5
    b := 3
    c := a + b*2
    d := (a + b) * 2
    e := a + b/2
    f := (a + b) / 2
    g := a*b + a/b
    h := a * (b + a) / b
}
```

# Complex Expressions

```ms
fn main() {
    let a = 5
    let b = 3
    let c = 2
    
    let result1 = a * b + c * (a - b) / (a + b)
    let result2 = (a * b + c) * (a - b) / (a + b * c)
    let result3 = a * (b + c * (a - b)) / (a + b * c)
    
    let bool_result1 = a > b && b > c || a == c
    let bool_result2 = a > b && (b > c || a == c)
    let bool_result3 = (a > b && b > c) || (a == c)
}
```

```go
package main

func main() {
    a := 5
    b := 3
    c := 2
    result1 := a*b + c*(a-b)/(a+b)
    result2 := (a*b + c) * (a - b) / (a + b*c)
    result3 := a * (b + c*(a-b)) / (a + b*c)
    bool_result1 := a > b && b > c || a == c
    bool_result2 := a > b && (b > c || a == c)
    bool_result3 := a > b && b > c || a == c
}
```

# String Expressions

```ms
fn main() {
    let (
        name = "World",
        greeting = "Hello, " + name + "!",
        multi_part = "The sum of " + "2 and 3 is " + "5",
        nested = "Value: " + ("x" + "y" + "z")
    )
}
```

```go
package main

func main() {
    name := "World"
    greeting := "Hello, " + name + "!"
    multi_part := "The sum of " + "2 and 3 is " + "5"
    nested := "Value: " + ("x" + "y" + "z")
}
```
# block let without comma

```ms
fn main() {
    let (
        name = "World"
        greeting = "Hello, " + name + "!"
        multi_part = "The sum of " + "2 and 3 is " + "5"
        nested = "Value: " + ("x" + "y" + "z")
    )
}
```

```go
package main

func main() {
    name := "World"
    greeting := "Hello, " + name + "!"
    multi_part := "The sum of " + "2 and 3 is " + "5"
    nested := "Value: " + ("x" + "y" + "z")
}
```

# Function Call Expressions

```ms
fn add(a int, b int) int {
    return a + b
}

fn mul(a int, b int) int {
    return a * b
}

fn main() {
    let result1 = add(5, 3)
    let result2 = mul(2, 4)
    
    let nested1 = add(mul(2, 3), 5)
    let nested2 = mul(add(1, 2), add(3, 4))
    
    let a = 10
    let b = 20
    let dynamic = add(a, b)
    
    let expr_args = add(5 + 3, b - a)
    return add(1, 2), add(4, 2)
}
```

```go
package main

func add(a int64, b int64) int64 {
    return a + b
}
func mul(a int64, b int64) int64 {
    return a * b
}
func main() {
    result1 := add(5, 3)
    result2 := mul(2, 4)
    nested1 := add(mul(2, 3), 5)
    nested2 := mul(add(1, 2), add(3, 4))
    a := 10
    b := 20
    dynamic := add(a, b)
    expr_args := add(5+3, b-a)
    return add(1, 2), add(4, 2)
}
```

# Method Call Expressions

```ms
type User {
    name string,
    age int
}

methods User as u {
    getName() string {
        u.name
    }
    
    isAdult() bool {
        u.age >= 18
    }
    
    birthday() {
        u.age += 1
    }
}

fn main() {
    let user = User(name: "Alice", age: 25)
    
    let name = user.getName()
    let is_adult = user.isAdult()
    
    user.birthday()
    let new_age = user.age
    
    let chained = User(name: "Bob", age: 30).getName()
}
```

```go
package main

type User struct {
    name string
    age  int64
}

func (u *User) getName() string {
    return u.name
}
func (u *User) isAdult() bool {
    return u.age >= 18
}
func (u *User) birthday() {
    u.age = u.age + 1
}
func main() {
    user := User{name: "Alice", age: 25}
    name := user.getName()
    is_adult := user.isAdult()
    user.birthday()
    new_age := user.age
    chained := User{name: "Bob", age: 30}.getName()
}
```

# Ternary Conditional Expressions

```ms
fn main() {
    let x = 10
    let y = 20
    
    let max = x > y ? x : y
    let min = x < y ? x : y
    
    let a = 5
    let b = 3
    let c = 7
    
    let nested = a > b ? (a > c ? a : c) : (b > c ? b : c)
    
    let expr_condition = (x + y > 25) ? "Greater" : "Less"
    let expr_values = x > y ? x + 5 : y - 5
}
```

```go
package main

func main() {
    x := 10
    y := 20
    max := func() interface{} {
        if x > y {
            return x
        } else {
            return y
        }
    }()
    min := func() interface{} {
        if x < y {
            return x
        } else {
            return y
        }
    }()
    a := 5
    b := 3
    c := 7
    nested := func() interface{} {
        if a > b {
            return func() interface{} {
                if a > c {
                    return a
                } else {
                    return c
                }
            }()
        } else {
            return func() interface{} {
                if b > c {
                    return b
                } else {
                    return c
                }
            }()
        }
    }()
    expr_condition := func() interface{} {
        if x+y > 25 {
            return "Greater"
        } else {
            return "Less"
        }
    }()
    expr_values := func() interface{} {
        if x > y {
            return x + 5
        } else {
            return y - 5
        }
    }()
}
``` 

# indexed access
```ms
let a = [1,2,3]
let b = a[1]
```

```go
package main

func main() {
    a := []interface{}{1, 2, 3}
    b := a[1]
}
```

# assignment
```ms
fn reassign() {
    let a = [1,2,3]
    let b = a[1]
    let c
    b = a[0]
    c = a[0]
}
```

```go
package main

func reassign() {
    a := []interface{}{1, 2, 3}
    b := a[1]
    var c
    b = a[0]
    c = a[0]
}
func main() {
}
```