Control Flow If Statements
---

# Basic If Statement

```ms
fn main() {
    let x = 10
    if x > 5 {
        print("x is greater than 5")
    }

    let y = 3
    if y > 5 {
        print("y is greater than 5")
    }
}
```

```go
package main

func main() {
    x := 10
    if x > 5 {
        print("x is greater than 5")
    }
    y := 3
    if y > 5 {
        print("y is greater than 5")
    }
}
```

# If-Else Statement

```ms
fn main() {
    let a = 7
    if a % 2 == 0 {
        print("a is even")
    } else {
        print("a is odd")
    }

    let b = 10
    if b % 2 == 0 {
        print("b is even")
    } else {
        print("b is odd")
    }
}
```

```go
package main

func main() {
    a := 7
    if a%2 == 0 {
        print("a is even")
    } else {
        print("a is odd")
    }
    b := 10
    if b%2 == 0 {
        print("b is even")
    } else {
        print("b is odd")
    }
}
```

# If-Else If-Else Chain

```ms
fn main() {
    let score = 85
    if score >= 90 {
        print("Grade A")
    } else {
        if score >= 80 {
            print("Grade B")
        } else {
            if score >= 70 {
                print("Grade C")
            } else {
                print("Grade D or F")
            }
            
            let score2 = 65
            if score2 >= 90 {
                print("Grade A")
            } else {
                if score2 >= 80 {
                    print("Grade B")
                } else {
                    if score2 >= 70 {
                        print("Grade C")
                    } else {
                        print("Grade D or F")
                    }
                }
            }
        }
    }
}
```

```go
package main

func main() {
    score := 85
    if score >= 90 {
        print("Grade A")
    } else {
        if score >= 80 {
            print("Grade B")
        } else {
            if score >= 70 {
                print("Grade C")
            } else {
                print("Grade D or F")
            }
            score2 := 65
            if score2 >= 90 {
                print("Grade A")
            } else {
                if score2 >= 80 {
                    print("Grade B")
                } else {
                    if score2 >= 70 {
                        print("Grade C")
                    } else {
                        print("Grade D or F")
                    }
                }
            }
        }
    }
}
```

# Block Scope in If Statements

```ms
fn main() {
    let p = 5
    if p > 0 {
        let q = p * 2
        print(q) // q is 10
    }
    // print(q) // This would be an error if uncommented, q is not defined here

    if true {
        let r = 100
        print(r) // r is 100
    }
    // print(r) // This would be an error, r is not defined here

    let s = 20
    if s > 10 {
        print(s) // s is 20 (outer scope)
        let s = 30 // s is shadowed
        print(s) // s is 30 (inner scope)
    }
    print(s) // s is 20 (outer scope)
}
```

```go
package main

func main() {
    p := 5
    if p > 0 {
        q := p * 2
        print(q)
    }
    if true {
        r := 100
        print(r)
    }
    s := 20
    if s > 10 {
        print(s)
        s := 30
        print(s)
    }
    print(s)
}
```

# Nested If Statements

```ms
fn main() {
    let num = 15
    let str = "hello"

    if num > 10 {
        print("num is greater than 10")
        if str == "hello" {
            print("str is hello")
        } else {
            print("str is not hello")
        }
    } else {
        print("num is not greater than 10")
        if str == "world" {
            print("str is world")
        } else {
            print("str is not world")
        }
    }

    let num2 = 5
    let str2 = "world"
    if num2 > 10 {
        print("num2 is greater than 10") // Should not print
        if str2 == "hello" {
            print("str2 is hello")
        } else {
            print("str2 is not hello")
        }
    } else {
        print("num2 is not greater than 10")
        if str2 == "world" {
            print("str2 is world")
        } else {
            print("str2 is not world")
        }
    }
}
```

```go
package main

func main() {
    num := 15
    str := "hello"
    if num > 10 {
        print("num is greater than 10")
        if str == "hello" {
            print("str is hello")
        } else {
            print("str is not hello")
        }
    } else {
        print("num is not greater than 10")
        if str == "world" {
            print("str is world")
        } else {
            print("str is not world")
        }
    }
    num2 := 5
    str2 := "world"
    if num2 > 10 {
        print("num2 is greater than 10")
        if str2 == "hello" {
            print("str2 is hello")
        } else {
            print("str2 is not hello")
        }
    } else {
        print("num2 is not greater than 10")
        if str2 == "world" {
            print("str2 is world")
        } else {
            print("str2 is not world")
        }
    }
}
```

# Boolean Expressions in Conditions

```ms
fn main() {
    let isReady = true
    if isReady {
        print("System is ready.")
    }

    let hasError = false
    if hasError {
        print("Error detected!") // Should not print
    } else {
        print("No errors.")
    }

    let isUserAdmin = true
    let isDocumentPublic = false

    if isUserAdmin || isDocumentPublic {
        print("User can access the document (either admin or public doc).")
    }

    if !isDocumentPublic && isUserAdmin {
        print("User is admin and document is not public, proceed with caution.")
    }
}
```

```go
package main

func main() {
    isReady := true
    if isReady {
        print("System is ready.")
    }
    hasError := false
    if hasError {
        print("Error detected!")
    } else {
        print("No errors.")
    }
    isUserAdmin := true
    isDocumentPublic := false
    if isUserAdmin || isDocumentPublic {
        print("User can access the document (either admin or public doc).")
    }
    if !isDocumentPublic && isUserAdmin {
        print("User is admin and document is not public, proceed with caution.")
    }
}
```

# Comparison Operators in Conditions

```ms
fn main() {
    let val1 = 100
    let val2 = 200

    if val1 < val2 {
        print("val1 is less than val2")
    }

    if val1 == val2 {
        print("val1 is equal to val2") 
    } else {
        print("val1 is not equal to val2")
    }

    if (val1 > 50) && (val2 > 150) {
        print("Both conditions met: val1 > 50 AND val2 > 150")
    }

    let age = 25
    let minimumAge = 18
    let maximumAge = 65

    if age >= minimumAge && age <= maximumAge {
        print("Age is within the valid range.")
    } else {
        print("Age is outside the valid range.")
    }
}
```

```go
package main

func main() {
    val1 := 100
    val2 := 200
    if val1 < val2 {
        print("val1 is less than val2")
    }
    if val1 == val2 {
        print("val1 is equal to val2")
    } else {
        print("val1 is not equal to val2")
    }
    if val1 > 50 && val2 > 150 {
        print("Both conditions met: val1 > 50 AND val2 > 150")
    }
    age := 25
    minimumAge := 18
    maximumAge := 65
    if age >= minimumAge && age <= maximumAge {
        print("Age is within the valid range.")
    } else {
        print("Age is outside the valid range.")
    }
}
```

# Logical Operators in Conditions

```ms
fn main() {
    let c1 = true
    let c2 = false

    if c1 && c2 {
        print("c1 AND c2 is true") 
    } else {
        print("c1 AND c2 is false")
    }

    if c1 || c2 {
        print("c1 OR c2 is true")
    }

    if !c2 {
        print("NOT c2 is true")
    }

    let a = 5
    let b = 10
    let c = 15

    if (a < b) && (b < c) {
        print("a < b AND b < c")
    }

    if (a > b) || (b < c) {
        print("a > b OR b < c")
    }

    if !(a > b) {
        print("NOT (a > b) is true")
    }
}
```

```go
package main

func main() {
    c1 := true
    c2 := false
    if c1 && c2 {
        print("c1 AND c2 is true")
    } else {
        print("c1 AND c2 is false")
    }
    if c1 || c2 {
        print("c1 OR c2 is true")
    }
    if !c2 {
        print("NOT c2 is true")
    }
    a := 5
    b := 10
    c := 15
    if a < b && b < c {
        print("a < b AND b < c")
    }
    if a > b || b < c {
        print("a > b OR b < c")
    }
    if !(a > b) {
        print("NOT (a > b) is true")
    }
}
``` 