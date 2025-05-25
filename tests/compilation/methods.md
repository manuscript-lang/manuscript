methods
---

# methods on a struct
```ms
type Logger {
    messages string[]
}

interface ILogger {
    log(message string, args any) 
}

methods Logger as r {
    log(message string, args any) {
        let a = 10
        r.messages.push(10)
    }
}

methods Logger as l {
    rotateFile() bool! { }
}
```

```go
package main

type Logger struct {
    messages []string
}
type ILogger interface {
    log(message string, args any)
}

func (r *Logger) log(message string, args any) {
    a := 10
    return r.messages.push(10)
}
func (l *Logger) rotateFile() (bool, error) {
}
func main() {
}
```
