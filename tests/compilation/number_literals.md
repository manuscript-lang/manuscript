# Integer literals with underscores

```ms
fn main() {
  let small = 1_000
  let medium = 100_000
  let large = 1_000_000
  let veryLarge = 1_000_000_000
}
```

```go
package main

func main() {
    small := 1_000
    medium := 100_000
    large := 1_000_000
    veryLarge := 1_000_000_000
}
```

# Hexadecimal literals with underscores

```ms
fn main() {
  let color = 0xFF_FF_FF
  let address = 0xDEAD_BEEF
  let mask = 0x00_FF_00_FF
}
```

```go
package main

func main() {
    color := 0xFF_FF_FF
    address := 0xDEAD_BEEF
    mask := 0x00_FF_00_FF
}
```

# Binary literals with underscores

```ms
fn main() {
  let flags = 0b1010_1010_1010_1010
  let mask = 0b1111_0000_1111_0000
  let pattern = 0b0101_0101
}
```

```go
package main

func main() {
    flags := 0b1010_1010_1010_1010
    mask := 0b1111_0000_1111_0000
    pattern := 0b0101_0101
}
```

# Octal literals with underscores

```ms
fn main() {
  let permissions = 0o755_644
  let value = 0o123_456_777
}
```

```go
package main

func main() {
    permissions := 0o755_644
    value := 0o123_456_777
}
```

# Float literals with underscores

```ms
fn main() {
  let pi = 3.14_159_265
  let large = 1_000.5_5
  let scientific = 1_000e+3
  let scientificFloat = 2.5_5e-10
}
```

```go
package main

func main() {
    pi := 3.14_159_265
    large := 1_000.5_5
    scientific := 1_000e+3
    scientificFloat := 2.5_5e-10
}
```

# Mixed number formats

```ms
fn main() {
  let decimal = 42_000
  let hex = 0xA_B_C_D
  let binary = 0b1100_1100
  let octal = 0o777_000
  let float = 123.45_67
}
```

```go
package main

func main() {
    decimal := 42_000
    hex := 0xA_B_C_D
    binary := 0b1100_1100
    octal := 0o777_000
    float := 123.45_67
}
```
