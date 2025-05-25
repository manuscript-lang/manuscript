# Basic piped statement
```ms
fn main() {
  source | fn1 arg1=val1 arg2=val2 | fn2 | fn3 arg1=val1
}
```
```go
package main

func main() {
    {
        proc1 := fn1(val1, val2)
        proc2 := fn2(val1)
        proc3 := fn3()
        for _, v := range source() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
        }
    }
}
```
---
# Simple piped statement with one function
```ms
fn main() {
  data | process
}
```
```go
package main

func main() {
    {
        proc1 := process()
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
        }
    }
}
```
---
# Piped statement with function call as source
```ms
fn main() {
  getData() | transform | filter
}
```
```go
package main

func main() {
    {
        proc1 := transform()
        proc2 := filter()
        for _, v := range getData() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Piped statement with multiple arguments
```ms
fn main() {
  numbers | multiply factor=2 | add offset=10 | format precision=2
}
```
```go
package main

func main() {
    {
        proc1 := multiply(2)
        proc2 := add(10)
        proc3 := format(2)
        for _, v := range numbers() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
        }
    }
}
```
---
# Piped statement with complex expressions as arguments
```ms
fn main() {
  items | filter condition=x > 5 | map transform=x * 2
}
```
```go
package main

func main() {
    {
        proc1 := filter(x > 5)
        proc2 := map(x * 2)
        for _, v := range items() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Single function with no arguments
```ms
fn main() {
  data | clean
}
```
```go
package main

func main() {
    {
        proc1 := clean()
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
        }
    }
}
```
---
# Multiple functions with no arguments
```ms
fn main() {
  stream | validate | normalize | save
}
```
```go
package main

func main() {
    {
        proc1 := validate()
        proc2 := normalize()
        proc3 := save()
        for _, v := range stream() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
        }
    }
}
```
---
# Mixed arguments and no arguments
```ms
fn main() {
  data | filter | transform scale=2 | output
}
```
```go
package main

func main() {
    {
        proc1 := filter(2)
        proc2 := transform()
        proc3 := output()
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
        }
    }
}
```
---
# Complex argument expressions
```ms
fn main() {
  values | scale factor=getMultiplier() | offset amount=base + delta
}
```
```go
package main

func main() {
    {
        proc1 := scale(getMultiplier())
        proc2 := offset(base + delta)
        for _, v := range values() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Multiple arguments with complex expressions
```ms
fn main() {
  items | process mode=getMode() threshold=max * 0.8 | format template=getTemplate()
}
```
```go
package main

func main() {
    {
        proc1 := process(getMode(), max*0.8)
        proc2 := format(getTemplate())
        for _, v := range items() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Nested function calls in arguments
```ms
fn main() {
  data | transform func=createTransformer(config) | validate rules=getRules(strict)
}
```
```go
package main

func main() {
    {
        proc1 := transform(createTransformer(config))
        proc2 := validate(getRules(strict))
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# String and numeric literals as arguments
```ms
fn main() {
  text | split delimiter="," | limit count=100 | join separator="|"
}
```
```go
package main

func main() {
    {
        proc1 := split(",")
        proc2 := limit(100)
        proc3 := join("|")
        for _, v := range text() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
        }
    }
}
```
---
# Boolean expressions as arguments
```ms
fn main() {
  records | filter active=true | validate strict=false | save force=enabled
}
```
```go
package main

func main() {
    {
        proc1 := filter(true)
        proc2 := validate(false)
        proc3 := save(enabled)
        for _, v := range records() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
        }
    }
}
```
---
# Long pipeline with many functions
```ms
fn main() {
  input | stage1 | stage2 | stage3 config=settings | stage4 | stage5 mode=fast
}
```
```go
package main

func main() {
    {
        proc1 := stage1(settings)
        proc2 := stage2(fast)
        proc3 := stage3()
        proc4 := stage4()
        proc5 := stage5()
        for _, v := range input() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
            a5 := proc4(a4)
            a6 := proc5(a5)
        }
    }
}
```
---
# Single argument with identifier
```ms
fn main() {
  data | transform value=x
}
```
```go
package main

func main() {
    {
        proc1 := transform(x)
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
        }
    }
}
```
---
# Multiple single-argument functions
```ms
fn main() {
  stream | filter predicate=isValid | map func=toUpper | reduce accumulator=sum
}
```
```go
package main

func main() {
    {
        proc1 := filter(isValid)
        proc2 := map(toUpper)
        proc3 := reduce(sum)
        for _, v := range stream() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
        }
    }
}
```
---
# Mixed literal types as arguments
```ms
fn main() {
  data | process count=42 rate=3.14 enabled=true name="test"
}
```
```go
package main

func main() {
    {
        proc1 := process(42, 3.14, true, "test")
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
        }
    }
}
```
---
# Complex nested expressions
```ms
fn main() {
  items | filter condition=getValue(key) > threshold * factor | transform func=createMapper(config.mode)
}
```
```go
package main

func main() {
    {
        proc1 := filter(getValue(key) > threshold*factor)
        proc2 := transform(createMapper(config.mode))
        for _, v := range items() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Very long pipeline
```ms
fn main() {
  data | step1 | step2 | step3 | step4 | step5 | step6 | step7 | step8 | step9 | step10
}
```
```go
package main

func main() {
    {
        proc1 := step1()
        proc2 := step2()
        proc3 := step3()
        proc4 := step4()
        proc5 := step5()
        proc6 := step6()
        proc7 := step7()
        proc8 := step8()
        proc9 := step9()
        proc10 := step10()
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
            a5 := proc4(a4)
            a6 := proc5(a5)
            a7 := proc6(a6)
            a8 := proc7(a7)
            a9 := proc8(a8)
            a10 := proc9(a9)
            a11 := proc10(a10)
        }
    }
}
```
---
# Function call with complex source
```ms
fn main() {
  getDataSource(config, mode) | validate | process
}
```
```go
package main

func main() {
    {
        proc1 := validate()
        proc2 := process()
        for _, v := range getDataSource(config, mode) {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Arguments with array access
```ms
fn main() {
  data | transform index=arr[0] value=map[key]
}
```
```go
package main

func main() {
    {
        proc1 := transform(arr[0], map[key])
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
        }
    }
}
```
---
# Arguments with method calls
```ms
fn main() {
  stream | filter condition=obj.isValid() | map func=obj.transform()
}
```
```go
package main

func main() {
    {
        proc1 := filter(obj.isValid())
        proc2 := map(obj.transform())
        for _, v := range stream() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Mixed argument order
```ms
fn main() {
  data | process first=1 second=getValue() third="text" fourth=true
}
```
```go
package main

func main() {
    {
        proc1 := process(1, getValue(), "text", true)
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
        }
    }
}
```
---
# Array literal as source
```ms
fn main() {
  [1, 2, 3] | transform | validate
}
```
```go
package main

func main() {
    {
        proc1 := transform()
        proc2 := validate()
        for _, v := range []interface{}{1, 2, 3}() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Complex expression as source
```ms
fn main() {
  (getItems() + moreItems) | filter | process
}
```
```go
package main

func main() {
    {
        proc1 := filter()
        proc2 := process()
        for _, v := range (getItems() + moreItems)() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Method call as source
```ms
fn main() {
  obj.getData() | transform | save
}
```
```go
package main

func main() {
    {
        proc1 := transform()
        proc2 := save()
        for _, v := range obj.getData() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Method call in intermediate step
```ms
fn main() {
  data | processor.transform | validate
}
```
```go
package main

func main() {
    {
        proc1 := processor.transform
        proc2 := validate()
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Multiple method calls in pipeline
```ms
fn main() {
  source | parser.extract | validator.validate | formatter.output
}
```
```go
package main

func main() {
    {
        proc1 := parser.extract
        proc2 := validator.validate
        proc3 := formatter.output
        for _, v := range source() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
        }
    }
}
```
---
# Mixed function and method calls
```ms
fn main() {
  data | transform | processor.validate | save
}
```
```go
package main

func main() {
    {
        proc1 := transform()
        proc2 := processor.validate
        proc3 := save()
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
            a4 := proc3(a3)
        }
    }
}
```
---
# Method call with arguments
```ms
fn main() {
  items | processor.filter condition=x > 5 | transform
}
```
```go
package main

func main() {
    {
        proc1 := processor.filter(x > 5)
        proc2 := transform()
        for _, v := range items() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Complex postfix expressions as source
```ms
fn main() {
  obj.getProcessor().getData() | transform | save
}
```
```go
package main

func main() {
    {
        proc1 := transform()
        proc2 := save()
        for _, v := range obj.getProcessor().getData() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Complex postfix expressions as targets
```ms
fn main() {
  data | factory.createProcessor() | utils.getValidator()
}
```
```go
package main

func main() {
    {
        proc1 := factory.createProcessor()
        proc2 := utils.getValidator()
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Method chains in pipeline targets
```ms
fn main() {
  source | processor.chain().withConfig() | validator.strict().enabled()
}
```
```go
package main

func main() {
    {
        proc1 := processor.chain().withConfig()
        proc2 := validator.strict().enabled()
        for _, v := range source() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Function calls with arguments as targets
```ms
fn main() {
  data | createFilter(strict) | buildValidator(mode)
}
```
```go
package main

func main() {
    {
        proc1 := createFilter(strict)
        proc2 := buildValidator(mode)
        for _, v := range data() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```
---
# Array access in pipeline
```ms
fn main() {
  items | processors[0] | validators[active]
}
```
```go
package main

func main() {
    {
        proc1 := processors[0]
        proc2 := validators[active]
        for _, v := range items() {
            a1 := v
            a2 := proc1(a1)
            a3 := proc2(a2)
        }
    }
}
```