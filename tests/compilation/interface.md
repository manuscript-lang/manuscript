interface tests
---

# basic interface
```ms
interface IWriter {
    write(data Buffer) void
}
```

```go
package main

type IWriter interface {
    write(data Buffer)
}

func main() {
}
```

# complex interface
```ms
interface IFileSystem {
    readFile(path string) Buffer
    writeFile(path string, data Buffer) void
    exists(path string) boolean
    listDir(path string) string[]
}
```

```go
package main

type IFileSystem interface {
    readFile(path string) Buffer
    writeFile(path string, data Buffer)
    exists(path string) boolean
    listDir(path string) []string
}

func main() {
}
```

# minimal interface with newlines
```ms
interface Minimal {
    foo() void

    bar() int
}
```

```go
package main

type Minimal interface {
    foo()
    bar() int64
}

func main() {
}
```
