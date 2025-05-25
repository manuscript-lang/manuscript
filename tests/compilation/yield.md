# Yield Statement Compilation Tests
---

# Basic Yield Statement

```ms
fn generator() {
    yield 1
    yield 2
    yield 3
}

fn main() {
    let ch = generator()
    for value in ch {
        print(value)
    }
}
```

```go
package main

func generator() chan interface {
} {
    ch := make(chan interface {
    }, 1)
    go func() {
        ch <- 1
        ch <- 2
        ch <- 3
        close(ch)
    }()
    return ch
}
func main() {
    ch := generator()
    for _, value := range ch {
        print(value)
    }
}
```

# Yield with Variables

```ms
fn numberGenerator(start int, end int) {
    let i = start
    while i <= end {
        yield i
        i += 1
    }
}

fn main() {
    let numbers = numberGenerator(1, 5)
    for num in numbers {
        print(num)
    }
}
```

```go
package main

func numberGenerator(start int64, end int64) chan interface {
} {
    ch := make(chan interface {
    }, 1)
    go func() {
        i := start
        for i <= end {
            ch <- i
            i = i + 1
        }
        close(ch)
    }()
    return ch
}
func main() {
    numbers := numberGenerator(1, 5)
    for _, num := range numbers {
        print(num)
    }
}
```

# Yield Multiple Values

```ms
fn pairGenerator() {
    yield 1, "first"
    yield 2, "second"
    yield 3, "third"
}

fn main() {
    let pairs = pairGenerator()
    for pair in pairs {
        print(pair)
    }
}
```

```go
package main

func pairGenerator() chan interface {
} {
    ch := make(chan interface {
    }, 1)
    go func() {
        ch <- []interface {
        }{1, "first"}
        ch <- []interface {
        }{2, "second"}
        ch <- []interface {
        }{3, "third"}
        close(ch)
    }()
    return ch
}
func main() {
    pairs := pairGenerator()
    for _, pair := range pairs {
        print(pair)
    }
}
```

# Yield in Conditional

```ms
fn conditionalGenerator(flag bool) {
    if flag {
        yield "true case"
    } else {
        yield "false case"
    }
    yield "always"
}

fn main() {
    let gen1 = conditionalGenerator(true)
    let gen2 = conditionalGenerator(false)
    
    for value in gen1 {
        print(value)
    }
    
    for value in gen2 {
        print(value)
    }
}
```

```go
package main

func conditionalGenerator(flag bool) chan interface {
} {
    ch := make(chan interface {
    }, 1)
    go func() {
        if flag {
            ch <- "true case"
        } else {
            ch <- "false case"
        }
        ch <- "always"
        close(ch)
    }()
    return ch
}
func main() {
    gen1 := conditionalGenerator(true)
    gen2 := conditionalGenerator(false)
    for _, value := range gen1 {
        print(value)
    }
    for _, value := range gen2 {
        print(value)
    }
}
```

# Yield in Loop

```ms
fn fibonacciGenerator(n int) {
    let a = 0
    let b = 1
    let i = 0
    
    while i < n {
        yield a
        let temp = a + b
        a = b
        b = temp
        i += 1
    }
}

fn main() {
    let fib = fibonacciGenerator(10)
    for value in fib {
        print(value)
    }
}
```

```go
package main

func fibonacciGenerator(n int64) chan interface {
} {
    ch := make(chan interface {
    }, 1)
    go func() {
        a := 0
        b := 1
        i := 0
        for i < n {
            ch <- a
            temp := a + b
            a = b
            b = temp
            i = i + 1
        }
        close(ch)
    }()
    return ch
}
func main() {
    fib := fibonacciGenerator(10)
    for _, value := range fib {
        print(value)
    }
}
```

# Empty Yield

```ms
fn emptyYieldGenerator() {
    yield
    yield
}

fn main() {
    let gen = emptyYieldGenerator()
    for value in gen {
        print(value)
    }
}
```

```go
package main

func emptyYieldGenerator() chan interface {
} {
    ch := make(chan interface {
    }, 1)
    go func() {
        ch <- nil
        ch <- nil
        close(ch)
    }()
    return ch
}
func main() {
    gen := emptyYieldGenerator()
    for _, value := range gen {
        print(value)
    }
}
```

# Yield with Expressions

```ms
fn expressionGenerator() {
    let x = 5
    yield x * 2
    yield x + 10
    yield x - 3
}

fn main() {
    let gen = expressionGenerator()
    for value in gen {
        print(value)
    }
}
```

```go
package main

func expressionGenerator() chan interface {
} {
    ch := make(chan interface {
    }, 1)
    go func() {
        x := 5
        ch <- x*2
        ch <- x+10
        ch <- x-3
        close(ch)
    }()
    return ch
}
func main() {
    gen := expressionGenerator()
    for _, value := range gen {
        print(value)
    }
}
```

# Function with Both Yield and Return

```ms
fn mixedGenerator(shouldYield bool) {
    if shouldYield {
        yield "yielding"
        yield "more values"
    } else {
        return
    }
    yield "final value"
}

fn main() {
    let gen1 = mixedGenerator(true)
    let gen2 = mixedGenerator(false)
    
    for value in gen1 {
        print(value)
    }
    
    for value in gen2 {
        print(value)
    }
}
```

```go
package main

func mixedGenerator(shouldYield bool) chan interface {
} {
    ch := make(chan interface {
    }, 1)
    go func() {
        if shouldYield {
            ch <- "yielding"
            ch <- "more values"
        } else {
            close(ch)
            return
        }
        ch <- "final value"
        close(ch)
    }()
    return ch
}
func main() {
    gen1 := mixedGenerator(true)
    gen2 := mixedGenerator(false)
    for _, value := range gen1 {
        print(value)
    }
    for _, value := range gen2 {
        print(value)
    }
}
``` 