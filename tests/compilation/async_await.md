# basic
```ms
fn doWork() {
    1 + 1
}

fn main() {
    async doWork()
    go doWork()
}
```
```go
package main

func doWork() {
    return 1 + 1
}
func main() {
    go doWork()
    go doWork()
}
```

---
# function calls with arguments
```ms
fn worker(x int) {
    x + 1
}

fn main() {
    async worker(42)
    go worker(100)
}
```
```go
package main

func worker(x int) {
    return x + 1
}
func main() {
    go worker(42)
    go worker(100)
}
```

---
# method calls
```ms
type Counter {
    value int
}

methods Counter as c {
    increment() {
        c.value = c.value + 1
    }
}

fn main() {
    let counter = Counter{value: 0}
    async counter.increment()
    go counter.increment()
}
```
```go
package main

type Counter struct {
    value int
}

func (c *Counter) increment() {
    c.value = c.value + 1
}
func main() {
    counter := &Counter{value: 0}
    go counter.increment()
    go counter.increment()
}
``` 