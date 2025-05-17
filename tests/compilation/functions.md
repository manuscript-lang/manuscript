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

# With a bang
```ms
fn save(item: Type): Type! {
  // function body
}
```
```go
package main

func save(item Type) (Type, error) {
}
func main() {
}
```

# default arguments
```ms
fn greet(name: string = "World") {
  print("Hello, " + name)
}

fn main() {
  greet()
  greet("Test")
}
```
```go
package main

func greet(args ...interface{}) {
    var name string = "World"
    if len(args) > 0 {
        name = args[0].(string)
    }
    print("Hello, " + name)
}
func main() {
    greet()
    greet("Test")
}
```

# Test function with multiple arguments, some with defaults
```ms
fn createUser(username: string, isActive: bool = true, retries: int = 3) {
  print(username + " " + string(isActive) + " " + string(retries))
}

fn main() {
  createUser("user1")
  createUser("user2", false)
  createUser("user3", true, 5)
}
```
```go
package main

func createUser(args ...interface{}) {
    username := args[0].(string)
    var isActive bool = true
    if len(args) > 1 {
        isActive = args[1].(bool)
    }
    var retries int64 = 3
    if len(args) > 2 {
        retries = args[2].(int64)
    }
    print(username + " " + string(isActive) + " " + string(retries))
}
func main() {
    createUser("user1")
    createUser("user2", false)
    createUser("user3", true, 5)
}
```

