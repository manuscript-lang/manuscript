+++
title = "Native functions"
weight = 3
+++

# Native functions

`extern fn` declares a function whose body is native code linked into the program. The Manuscript name is the symbol name, so `extern fn llabs(value Int) Int` calls the native symbol `llabs`. To use another Manuscript name, wrap the extern in an ordinary function.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

extern fn llabs(value Int) Int

fn magnitude(value Int) Int {
    return llabs(value)
}

test "an extern calls the native symbol" {
    expect_equal(magnitude(-7), 7)?
}
```

An extern has no body and no trailing `:`. It may be exported. It cannot be generic, take defaults or `var` parameters, or be a method.

How a program supplies its own native code is not documented yet.
