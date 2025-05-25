```ms
fn main() {
  // Empty main for an empty ms block
}
```

```go
package main

func main() {
}
```

```ms
fn main() {
  let x // This might still fail if let must be initialized by current grammar
}
```

```go
package main

func main() {
    var x
}
```

```ms
fn main() {
  let x = 10;
  let message = 'hello';
  let multiLine = '''
This is a multi-line string.
It can contain multiple lines of text.
'''
  let multiLine2 = 'This is another multi-line string. 
It can also contain multiple lines of text.
'
  let dq = "double quoted"
  let dtq = """
  double triple quoted
  """

  let bin = 0b010101
  let hex = 0xFFF
  let oct = 0o1023
  let (
    n = null
    v = void
  )
}
```

```go
package main

func main() {
    x := 10
    message := "hello"
    multiLine := "\nThis is a multi-line string.\nIt can contain multiple lines of text.\n"
    multiLine2 := "This is another multi-line string. \nIt can also contain multiple lines of text.\n"
    dq := "double quoted"
    dtq := "\n  double triple quoted\n  "
    bin := 0b010101
    hex := 0xFFF
    oct := 0o1023
    n := nil
    v := nil
}
``` 

```ms
fn main() {
  let a = 5;
  let b = 10;
  let c = 15;
  let x; // Assuming this should parse as a declaration
  let y; // Assuming this should parse as a declaration
  let z = 20;
}
```

```go
package main

func main() {
    a := 5
    b := 10
    c := 15
    var x
    var y
    z := 20
}
```

```ms
fn main() {
  let decimal = 1_000_000
  let hex = 0xFF_FF_FF
  let binary = 0b1010_1010_1010_1010
  let octal = 0o777_777
  let float1 = 3.14_159
  let float2 = 1_000.5_5
  let scientific = 1_000e+3
}
```

```go
package main

func main() {
    decimal := 1_000_000
    hex := 0xFF_FF_FF
    binary := 0b1010_1010_1010_1010
    octal := 0o777_777
    float1 := 3.14_159
    float2 := 1_000.5_5
    scientific := 1_000e+3
}
```