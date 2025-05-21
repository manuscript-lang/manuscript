# Benchmark for Slow Parsing

```ms
let a = 1;

let b = 2;


let c = 3


;

fn foo() {
    let x = 10;

    let y = 20;
    return x + y;
}

;;;

let d = foo();


let e = a + b + c + d;
```

```go
package main

func foo() {
    x := 10
    y := 20
    return x + y
}
func main() {
    a := 1
    b := 2
    c := 3
    d := foo()
    e := a + b + c + d
}
```
