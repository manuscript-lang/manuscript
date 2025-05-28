types
---

# Test function with custom type parameter
```ms
type Point {
  x int,
  y int
}

fn printPoint(p Point) {
  print(p.x)
  print(p.y)
}

fn main() {
  let pt = Point{x: 1, y: 2}
  printPoint(pt)
}
```
```go
package main

type Point struct {
    x   int
    y   int
}

func printPoint(p Point) {
    print(p.x)
    return print(p.y)
}
func main() {
    pt := &Point{x: 1, y: 2}
    printPoint(pt)
}
```

---
# Test function returning custom type
```ms
type User {
  id int,
  name string
}

fn createUser(id int, name string) User {
  let u = User{id: id, name: name}
  u
}

fn main() {
  let u = createUser(1, "Test User")
  print(u.id)
  print(u.name)
}
```
```go
package main

type User struct {
    id   int
    name string
}

func createUser(id int, name string) User {
    u := &User{id: id, name: name}
    return u
}
func main() {
    u := createUser(1, "Test User")
    print(u.id)
    print(u.name)
}
```

---
# Test function with custom type parameter and return
```ms
type Vector {
  dx float,
  dy float
}

fn scaleVector(v Vector, factor float) Vector {
  Vector{dx: v.dx * factor, dy: v.dy * factor}
}

fn main() {
  let vec = Vector{dx: 1.0, dy: 2.5}
  let scaledVec = scaleVector(vec, 2.0)
  print(scaledVec.dx)
  print(scaledVec.dy)
}
```
```go
package main

type Vector struct {
    dx  float64
    dy  float64
}

func scaleVector(v Vector, factor float64) Vector {
    return &Vector{dx: v.dx * factor, dy: v.dy * factor}
}
func main() {
    vec := &Vector{dx: 1.0, dy: 2.5}
    scaledVec := scaleVector(vec, 2.0)
    print(scaledVec.dx)
    print(scaledVec.dy)
}
```

---
# Test function with type alias for built-in type
```ms
type UserID = int

fn printUserID(id UserID) {
  print(id)
}

fn main() {
  let userID = 123
  printUserID(userID)
}
```
```go
package main

type UserID int

func printUserID(id UserID) {
    return print(id)
}
func main() {
    userID := 123
    printUserID(userID)
}
```

# func as type
```ms

fn filter(arr int[], filterFunc fn (item int) bool) int[] {
  // .. body
}
```

```go
package main

func filter(arr []int, filterFunc func(item int) bool) []int {
}
func main() {
}
```

# typed object literal
```ms
type ServerConfig {
  url string,
  port int
}

fn main() {
  let a = ServerConfig {
    url: 'https://server.url',
    port: 8080
  }
  print(a.url)
}
```

```go
package main

type ServerConfig struct {
    url  string
    port int
}

func main() {
    a := &ServerConfig{url: "https://server.url", port: 8080}
    print(a.url)
}
```

---
# typed object literal with partial fields
```ms
type User {
  id int,
  name string,
  email string
}

fn main() {
  let u = User {
    id: 42,
    name: 'John Doe'
  }
  print(u.name)
}
```

```go
package main

type User struct {
    id    int
    name  string
    email string
}

func main() {
    u := &User{id: 42, name: "John Doe"}
    print(u.name)
}
```

---
# typed object literal with multiline string fields
```ms
type Document {
  title string,
  content string,
  metadata string
}

fn main() {
  let doc = Document {
    title: 'API Documentation',
    content: '''
      This is a multiline string
      that spans multiple lines
      and contains detailed content
    ''',
    metadata: """
      Created: 2024-01-01
      Author: System
      Version: 1.0
    """
  }
  print(doc.title)
  print(doc.content)
}
```

```go
package main

type Document struct {
    title    string
    content  string
    metadata string
}

func main() {
    doc := &Document{title: "API Documentation", content: "\n      This is a multiline string\n      that spans multiple lines\n      and contains detailed content\n    ", metadata: "\n      Created: 2024-01-01\n      Author: System\n      Version: 1.0\n    "}
    print(doc.title)
    print(doc.content)
}
```

