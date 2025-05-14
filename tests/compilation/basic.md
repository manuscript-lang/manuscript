```ms
```

```go
package main

func main() {
}
```

```ms
let x
```

```go
package main

func main() {
	var x
}
```

```ms
let x = 10;
let message = 'hello';
let multiLine = '''
This is a multi-line string.
It can contain multiple lines of text.
'''
let multiLine2 = 'This is another multi-line string. 
It can also contain multiple lines of text.
'
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
let a = 5, b = 10, c = 15;
let x, y, z = 20; // Only z gets a value, x and y are just declared
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