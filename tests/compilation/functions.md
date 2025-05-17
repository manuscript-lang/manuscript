```ms
fn main() {
  print("hello world")
}
```

```go
package main

func main() {
    print("hello world")
}
```
---
# Test function with parameters and no return
```ms
fn greet(name: string) {
  print("Hello, " + name)
}

fn main() {
  greet("World")
}
```
```go
package main

func greet(name string) {
    print("Hello, " + name)
}
func main() {
    greet("World")
}
```
---
# Test function with no parameters and a return value
```ms
fn get_pi(): float {
  3.14
}

fn main() {
  let x = get_pi()
  print(x)
}
```
```go
package main

func get_pi() float64 {
    return 3.14
}
func main() {
    x := get_pi()
    print(x)
}
```
---
# Test function with parmeters and a return value
```ms
fn add(a: int, b: int): int {
  let d = 10
  a + b + d
}

fn main() {
  let sum = add(5, 3)
  print(sum)
}
```
```go
package main

func add(a int64, b int64) int64 {
    d := 10
    return a + b + d
}
func main() {
    sum := add(5, 3)
    print(sum)
}
```