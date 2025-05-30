# should fail syntax
```ms
fn fn4() { 
    a(try b()) 
}
```
```go
ERR_SYNTAX
```
