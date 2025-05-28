let patterns
---

# basic
```ms
let a = 10
let b = ["asd", "Asds"]
let set = <1, 2, 3>
let map = [key: "value", another: 10]
let { a, b } = obj
let [c, d] = [1, 2]
let (
    e = 30,
    f = 30,
    g = true,
    {i, j} = {i: 10, j: false},
    [x, y] = ['x', 'y'],
)
```
```go
package main

func main() {
    a := 10
    b := []interface{}{"asd", "Asds"}
    set := map[interface{}]bool{1: true, 2: true, 3: true}
    map := map[interface{}]interface{}{key: "value", another: 10}
    __val1 := obj
    a := __val1.a
    b := __val1.b
    __val2 := []interface{}{1, 2}
    c := __val2[0]
    d := __val2[1]
    e := 30
    f := 30
    g := true
    __val3 := map[string]interface{}{"i": 10, "j": false}
    i := __val3.i
    j := __val3.j
    __val4 := []interface{}{"x", "y"}
    x := __val4[0]
    y := __val4[1]
}
```

# assignment
```ms
fn main () {
let a = [1,2,3]
let b = a[1]
let c
b = a[0]
c = a[1]
}
```

```go
package main

func main() {
    a := []interface{}{1, 2, 3}
    b := a[1]
    var c
    b = a[0]
    c = a[1]
}
```