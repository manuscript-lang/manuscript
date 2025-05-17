Control flow for loops
---
# Basic while loop
```ms
fn main() {
    let i = 0
    while i < 3 {
        print(i)
        i = i + 1
    }
}
```
```go
package main

func main() {
    i := 0
    for i < 3 {
        print(i)
        i = i + 1
    }
}
```
---
# While loop with break
```ms
fn main() {
    let i = 0
    while i < 5 {
        if i == 3 {
            break
        }
        print(i)
        i = i + 1
    }
}
```
```go
package main

func main() {
    i := 0
    for i < 5 {
        if i == 3 {
            break
        }
        print(i)
        i = i + 1
    }
}
```
---
# While loop with continue
```ms
fn main() {
    let i = 0
    while i < 5 {
        i = i + 1
        if i == 3 {
            continue
        }
        print(i)
    }
}
```
```go
package main

func main() {
    i := 0
    for i < 5 {
        i = i + 1
        if i == 3 {
            continue
        }
        print(i)
    }
}
```
---
# While false loop
```ms
fn main() {
    while false {
        print("unreachable")
    }
    print("done")
}
```
```go
package main

func main() {
    for false {
        print("unreachable")
    }
    print("done")
}
```
---
# While true loop with break (to prevent infinite loop)
```ms
fn main() {
    let i = 0
    while true {
        print(i)
        i = i + 1
        if i == 3 {
            break
        }
    }
}
```
```go
package main

func main() {
    i := 0
    for true {
        print(i)
        i = i + 1
        if i == 3 {
            break
        }
    }
}
```
---
# Basic C-style for loop
```ms
fn main() {
    for i = 0; i < 3; i = i + 1 {
        print(i)
    }
}
```
```go
package main

func main() {
    for i := 0; i < 3; i = i + 1 {
        print(i)
    }
}
```
---
# C-style for loop with break
```ms
fn main() {
    for i = 0; i < 5; i = i + 1 {
        if i == 3 {
            break
        }
        print(i)
    }
}
```
```go
package main

func main() {
    for i := 0; i < 5; i = i + 1 {
        if i == 3 {
            break
        }
        print(i)
    }
}
```
---
# C-style for loop with continue
```ms
fn main() {
    for i = 0; i < 5; i = i + 1 {
        if i == 2 {
            continue
        }
        print(i)
    }
}
```
```go
package main

func main() {
    for i := 0; i < 5; i = i + 1 {
        if i == 2 {
            continue
        }
        print(i)
    }
}
```
---
# Nested C-style for loops
```ms
fn main() {
    for i = 0;i < 2;i = i + 1 {
        for j = 0; j < 2; j = j + 1 {
            print(i * 10 + j)
        }
    }
}
```
```go
package main

func main() {
    for i := 0; i < 2; i = i + 1 {
        for j := 0; j < 2; j = j + 1 {
            print(i*10 + j)
        }
    }
}
```
---
# C-style for loop with empty body
```ms
fn main() {
    let i = 0
    for ; i < 3; i = i + 1 {}
    print(i)
}
```
```go
package main

func main() {
    i := 0
    for ; i < 3; i = i + 1 {
    }
    print(i)
}
```
---
# C-style for loop with no init
```ms
fn main() {
    let i = 0
    for ; i < 3; i = i + 1 {
        print(i)
    }
}
```
```go
package main

func main() {
    i := 0
    for ; i < 3; i = i + 1 {
        print(i)
    }
}
```
---
# C-style for loop with only condition
```ms
fn main() {
    let i = 0
    for ; i < 3; {
        print(i)
        i = i + 1
    }
}
```
```go
package main

func main() {
    i := 0
    for i < 3 {
        print(i)
        i = i + 1
    }
}
```
---
# For-in loop over array (value only)
```ms
fn main() {
    let arr = [10, 20, 30]
    for v in arr {
        print(v)
    }
}
```
```go
package main

func main() {
    arr := []interface{}{10, 20, 30}
    for _, v := range arr {
        print(v)
    }
}
```
---
# For-in loop over array (value and index)
```ms
fn main() {
    let arr = ["a", "b", "c"]
    for i, v in arr {
        print(i)
        print(v)
    }
}
```
```go
package main

func main() {
    arr := []interface{}{"a", "b", "c"}
    for v, i := range arr {
        print(i)
        print(v)
    }
}
```
---
# For-in loop over array with break
```ms
fn main() {
    let arr = [1, 2, 3, 4, 5]
    for v in arr {
        if v == 4 {
            break
        }
        print(v)
    }
}
```
```go
package main

func main() {
    arr := []interface{}{1, 2, 3, 4, 5}
    for _, v := range arr {
        if v == 4 {
            break
        }
        print(v)
    }
}
```
---
# For-in loop over array with continue
```ms
fn main() {
    let arr = [1, 2, 3, 4, 5]
    for v in arr {
        if v == 3 {
            continue
        }
        print(v)
    }
}
```
```go
package main

func main() {
    arr := []interface{}{1, 2, 3, 4, 5}
    for _, v := range arr {
        if v == 3 {
            continue
        }
        print(v)
    }
}
```
---
# C-style for loop with no condition (infinite loop with break)
```ms
fn main() {
    let i = 0
    for ; ; i = i + 1 {
        print(i)
        if i >= 3 { 
            break
        }
    }
}
```
```go
package main

func main() {
    i := 0
    for ; ; i = i + 1 {
        print(i)
        if i >= 3 {
            break
        }
    }
}
```
---
# C-style for loop with no post statement
```ms
fn main() {
    for i = 0; i < 3; {
        print(i)
        i = i + 1
    }
}
```
```go
package main

func main() {
    for i := 0; i < 3; {
        print(i)
        i = i + 1
    }
}
```
---
# C-style for loop with all parts empty (infinite loop with break)
```ms
fn main() {
    let i = 0
    for ;; { 
        print(i)
        i = i + 1
        if i == 3 {
            break
        }
    }
}
```
```go
package main

func main() {
    i := 0
    for {
        print(i)
        i = i + 1
        if i == 3 {
            break
        }
    }
}
```
---
# Basic For-in loop (single variable)
```ms
fn main() {
    let arr = [10, 20, 30]
    for val in arr {
        print(val)
    }
}
```
```go
package main

func main() {
    arr := []interface{}{10, 20, 30}
    for _, val := range arr {
        print(val)
    }
}
```
---
# For-in loop (key, value)
```ms
fn main() {
    let arr = [10, 20, 30]
    for idx, val in arr { 
        print(idx)
        print(val)
    }
}
```
```go
package main

func main() {
    arr := []interface{}{10, 20, 30}
    for val, idx := range arr {
        print(idx)
        print(val)
    }
}
```
---
# For-in loop with break
```ms
fn main() {
    let arr = [1, 2, 3, 4, 5]
    for val in arr {
        if val == 3 {
            break
        }
        print(val)
    }
}
```
```go
package main

func main() {
    arr := []interface{}{1, 2, 3, 4, 5}
    for _, val := range arr {
        if val == 3 {
            break
        }
        print(val)
    }
}
```
---
# For-in loop with continue
```ms
fn main() {
    let arr = [1, 2, 3, 4, 5]
    for val in arr {
        if val == 3 {
            continue
        }
        print(val)
    }
}
```
```go
package main

func main() {
    arr := []interface{}{1, 2, 3, 4, 5}
    for _, val := range arr {
        if val == 3 {
            continue
        }
        print(val)
    }
}
```
---
# For-in loop over an array literal
```ms
fn main() {
    for x in [100, 200, 300] {
        print(x)
    }
}
```
```go
package main

func main() {
    for _, x := range []interface{}{100, 200, 300} {
        print(x)
    }
}
```
---
# Nested for-in and C-style loops
```ms
fn main() {
    let data = [1, 2]
    for v in data {
        for i = 0; i < v; i = i + 1 { 
            print(v * 10 + i)
        }
    }
}
```
```go
package main

func main() {
    data := []interface{}{1, 2}
    for _, v := range data {
        for i := 0; i < v; i = i + 1 {
            print(v*10 + i)
        }
    }
}
```