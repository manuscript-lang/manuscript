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
| `Result[T, E]` result | `uint8_t` status, with `T` through a trailing `out` unless it is `Unit` |

A `Result[T, E]` return takes `Int`, `Float`, `Bool`, `String`, or `Unit` for `T`. `E` is a `type` whose cases all carry no payload. The native returns `0` for success, and `1`, `2`, ... for the first, second, ... case of `E` in declaration order. Reordering the cases of `E` changes the numbers, so the native must change with it. A status past the last case is read as the last case. `out` is written only when the status is `0`.

Any other type is rejected by `ms check`. C types such as `int`, `float`, `char *`, and structs have no Manuscript counterpart, so a library using them needs a small shim written against `crates/ms-rt-abi/include/ms_abi.h`.

Arguments are borrowed: a native reads them and does not keep the pointer after returning. A native builds string results only with `msrt_string_from_bytes`, never with its own allocator, so the program can free them. A native must not block indefinitely, since a native call is not a cancellation point.

## Extern types

`extern type Name` declares an opaque value whose layout the runtime owns, such as `Decimal`. Only the standard library may declare one; user modules get a diagnostic. A bundled module pairs it with private `extern fn` declarations and ordinary wrapper methods in an `impl` block, so the public API is plain Manuscript over the native symbols.

## Linking the native code

`ms build`, `ms run`, and `ms test` take `--link <file>` (repeatable) for an object (`.o`) or static library (`.a`) that defines the symbols. The standard runtime and libc are always linked.

```text
cc -c -I crates/ms-rt-abi/include greet.c -o greet.o
ms run main.ms --link greet.o
```

A symbol that no input defines fails the link, and the error names the symbol and suggests `--link`.
