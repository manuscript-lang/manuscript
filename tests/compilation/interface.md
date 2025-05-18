interface tests
---

# basic interface
```ms
interface IWriter {
    write(data: Buffer): void
}
```

```go
package main

interface IWriter interface {
    write(Buffer)
}

func main() {
}
```

# complex interface
```ms
interface IFileSystem {
    readFile(path: string): Buffer
    writeFile(path: string, data: Buffer): void
    exists(path: string): boolean
    listDir(path: string): string[]
}
```

```go
package main

interface IFileSystem interface {
    readFile(string) Buffer
    writeFile(string, Buffer)
    exists(string) boolean
    listDir(string) []string
}

func main() {
}
```