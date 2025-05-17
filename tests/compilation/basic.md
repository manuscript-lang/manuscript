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
}
```

```go
package main

func main() {
	x := 10
	message := "hello"
	multiLine := "\nThis is a multi-line string.\nIt can contain multiple lines of text.\n"
	multiLine2 := "This is another multi-line string. \nIt can also contain multiple lines of text.\n"
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