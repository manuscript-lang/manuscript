```ms
fn main() {
  print("hello world")
}
```

```go
package main

func main() {
    return print("hello world")
}
```
---
# Test function with parameters and no return
```ms
fn greet(name string) {
  print("Hello, " + name)
}

fn main() {
  greet("World")
}
```
```go
package main

func greet(name string) {
    return print("Hello, " + name)
}
func main() {
    return greet("World")
}
```
---
# Test function with no parameters and a return value
```ms
fn get_pi() float {
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
    return print(x)
}
```
---
# Test function with parmeters and a return value
```ms
fn add(a int, b int) int {
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
    return print(sum)
}
```

# With a bang
```ms
fn save(item Type) Type! {
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
fn greet(name string = "World") {
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
    return print("Hello, " + name)
}
func main() {
    greet()
    return greet("Test")
}
```

# Test function with multiple arguments, some with defaults
```ms
fn createUser(username string, isActive bool = true, retries int = 3) {
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
    return print(username + " " + string(isActive) + " " + string(retries))
}
func main() {
    createUser("user1")
    createUser("user2", false)
    return createUser("user3", true, 5)
}
```

# Test simple defer statement
```ms
fn cleanup() {
  print("cleaning up resources")
}

fn main() {
  print("starting work")
  defer cleanup()
  print("doing work")
}
```
```go
package main

func cleanup() {
    return print("cleaning up resources")
}
func main() {
    print("starting work")
    defer cleanup()
    return print("doing work")
}
```

# Test defer with function call
```ms
fn main() {
  let file = openFile("example.txt")
  defer file.close()
  
  // Use file here
  file.write("Hello, World!")
}

fn openFile(path string) File {
  // Open file implementation
  let file = File()
  return file
}
```
```go
package main

func main() {
    file := openFile("example.txt")
    defer file.close()
    return file.write("Hello, World!")
}
func openFile(path string) File {
    file := File()
    return file
}
```

# multiple return calls
```ms
fn doIt() {
   return a(), b(), c()
}
```
```go
package main

func doIt() {
    return a(), b(), c()
}
func main() {
}
```

# implicit returns

```ms
fn doIt() { 42 }
fn fn1() { 'val' }
fn fn2() { [] }
fn fn3() { <> }
fn fn4() { a() }
```
```go
package main

func doIt() {
    return 42
}
func fn1() {
    return "val"
}
func fn2() {
    return []interface{}{}
}
func fn3() {
    return map[interface{}]bool{}
}
func fn4() {
    return a()
}
func main() {
}
```

# try 
```ms
fn f1() {
  let a = try f2()
  let b = try f3()
  try f4()
}
```
```go
package main

func f1() {
    a, err := f2()
    if err != nil {
        return nil, err
    }
    b, err := f3()
    if err != nil {
        return nil, err
    }
    _, err := f4()
    if err != nil {
        return nil, err
    }
}
func main() {
}
```