+++
title = "Native functions"
weight = 3
+++

# Native functions

`extern fn` declares a function whose body is native code linked into the program. The Manuscript name is the symbol name, so `extern fn labs(value: Int) Int` calls the native symbol `labs`. To use another Manuscript name, wrap the extern in an ordinary function.

<!-- manuscript-example: test -->
```manuscript
import {expect_equal} from "@std/testing.ms"

extern fn labs(value: Int) Int

fn magnitude(value: Int) Int:
    return labs(value)

test "an extern calls the native symbol":
    expect_equal(magnitude(-7), 7)
```

An extern has no body and no trailing `:`. It may be exported. It cannot be generic, take defaults or `var` parameters, or be a method.

## Types that cross

An extern follows the runtime's native conventions (`ms-rt/ABI.md`, section 1).

| Manuscript | Native |
| --- | --- |
| `Int` | `int64_t` |
| `Float` | `double` (not C `float`) |
| `Bool` | `uint8_t`, 0 or 1 |
| `String` argument | `const ms_str *`, borrowed for the call |
| `String` result | trailing `ms_str *out`, filled by `msrt_string_from_bytes` |
| `Unit` result | `void` |

Any other type is rejected by `ms check`. C types such as `int`, `float`, `char *`, and structs have no Manuscript counterpart, so a library using them needs a small shim written against `crates/ms-rt-abi/include/ms_abi.h`.

Arguments are borrowed: a native reads them and does not keep the pointer after returning. A native builds string results only with `msrt_string_from_bytes`, never with its own allocator, so the program can free them. A native must not block indefinitely, since a native call is not a cancellation point.

## Linking the native code

`ms build`, `ms run`, and `ms test` take `--link <file>` (repeatable) for an object (`.o`) or static library (`.a`) that defines the symbols. The standard runtime and libc are always linked.

```text
cc -c -I crates/ms-rt-abi/include greet.c -o greet.o
ms run main.ms --link greet.o
```

A symbol that no input defines fails the link, and the error names the symbol and suggests `--link`.
