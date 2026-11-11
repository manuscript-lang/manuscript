+++
title = "Native functions"
weight = 3
+++

# Native functions

`extern fn` declares a function whose body is native code linked into the program. The Manuscript name is the symbol name, so `extern fn llabs(value: Int) Int` calls the native symbol `llabs`. To use another Manuscript name, wrap the extern in an ordinary function.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

extern fn llabs(value: Int) Int

fn magnitude(value: Int) Int:
    return llabs(value)

test "an extern calls the native symbol":
    expect_equal(magnitude(-7), 7)?
```

An extern has no body and no trailing `:`. It may be exported. It cannot be generic, take defaults or `var` parameters, or be a method.

## Types that cross

An extern follows `crates/ms-rt-abi/include/ms_abi.h`, which a C shim includes.

| Manuscript | C parameter | C result |
| --- | --- | --- |
| `Int`, `Int8` ... `Int32`, `UInt8` ... `UInt64` | `int64_t`, `int8_t` ... `uint64_t` | same |
| `Float`, `Float32` | `double`, `float` | same |
| `Bool` | `bool` | same |
| `String` | `const ms_str *`, borrowed | trailing `ms_str *out` |
| `Bytes` | `const ms_bytes *`, borrowed | trailing `ms_bytes *out` |
| `List[T]`, `T` one of the types above or an extern type | `const ms_list *`, borrowed | trailing `ms_list *out` |
| an `extern type` | `ms_object *`, borrowed | `ms_object *`, owned by the program |
| `fn(A, B) R`, each `A` a number, `Bool`, `String`, `Bytes` or extern type, `R` one of those but an extern type, or `Unit` | `ms_fn *`, borrowed | not allowed |
| `Unit` | not allowed | `void` |
| `Result[T, E]` | not allowed | `uint8_t` status, `T` through `out`, then `code_out`, `message_out` |

Any other type is rejected by `ms check`. A type, enum, map or optional is converted in an ordinary Manuscript function around the extern.

Arguments are borrowed: a native reads them and does not keep a pointer after returning. It builds results with `ms_string_new`, `ms_bytes_new` and `ms_list_push`, never with its own allocator, so the program can free them. A list knows its element type: `ms_list_get` widens an element into an `ms_value`, and `ms_list_push` faults on a value of another kind or out of the element's range. Strings and bytes from `ms_list_get` are `malloc` copies that `ms_value_free` releases. A native that blocks, such as an event loop, returns when a stop is requested only if it registers a stop hook (see [Calling back into Manuscript](#calling-back-into-manuscript)), since a native call is not a cancellation point.

Every output arrives holding an empty value (0, `""`, an empty list, NULL), and the program drops every output after the call. A native that writes the wrong output, or none, therefore leaves nothing undefined. An object result that is still NULL faults.

## Errors

A `Result[T, E]` return names its error type `E`, an enum whose cases carry nothing, `code: Int`, `message: String`, or both. The native returns `0` for success, and `1`, `2`, ... for the first, second, ... case of `E` in declaration order; reordering the cases changes the numbers. When any case has a `code` field, a trailing `int64_t *code_out` follows `out`; when any has a `message`, a trailing `ms_str *message_out` follows. The program reads the fields of the case the status names. A status that names no case faults.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
// A failed call, with the library's code and description.
enum LibraryError:
    Failed(code: Int, message: String)
    Busy

extern fn lib_count(path: String) Int!LibraryError
```

```c
#include "ms_abi.h"

uint8_t lib_count(const ms_str *path, int64_t *out, int64_t *code_out, ms_str *message_out) {
    int rc = count_entries(ms_str_data(path), ms_str_len(path), out);
    if (rc == BUSY) return 2;                        /* LibraryError.Busy */
    if (rc != 0) {
        *code_out = rc;
        const char *text = describe(rc);
        size_t len = 0;
        while (text[len]) len++;
        ms_string_new((const uint8_t *)text, len, message_out);
        return 1;                                    /* LibraryError.Failed */
    }
    return 0;
}
```

`ms_fault(text, len)` ends the program like a Manuscript fault, running cleanups first.

## Extern types

`extern type Name` declares an opaque handle that a native makes with `ms_object_new(size, drop)`: `size` zeroed payload bytes at a stable address (`ms_payload`), and a `drop` (or NULL) that runs once when its owner drops it. A handle has one owner and cannot be copied (`.clone()` is rejected and `ms_object_clone` of one faults); a native that made a handle and does not return it drops it with `ms_object_drop`. An extern type has no fields and cannot be generic. Pair it with private externs and an `impl` block so the public API is plain Manuscript.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import Closeable from "@std/core.ms"

// A connection the native library owns.
export extern type Connection

extern fn lib_connect(address: String) Connection
extern fn lib_disconnect(connection: Connection) Unit

fn var Connection.close() Unit!:
    lib_disconnect(self)
```

## Calling back into Manuscript

A function argument reaches the native as an `ms_fn *`, which `ms_call(f, args, count, result)` calls on the same thread with an array of `ms_value`s. Each argument must have the kind and range of its parameter (`MS_INT` for a signed type, `MS_UINT` for an unsigned one), or `ms_call` faults before the call. `result`, which may be NULL, receives the value as `ms_list_get` gives it. A fault in the function ends the program like any fault; `ms_call` does not return from it. A function takes at most six parameters.

A native that keeps a function past the call, for a library that calls back later, takes its own copy with `ms_fn_clone` and drops it with `ms_fn_drop`. It calls the function only on the thread that called the native. Because a native may keep it, a closure passed to an extern owns what it captures.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
// Calls `visit` once for each entry the library finds.
extern fn lib_walk(root: String, visit: fn(String, Int) Unit) Unit
```

```c
#include "ms_abi.h"

static void each_entry(const char *name, size_t len, int64_t size, void *data) {
    ms_value args[2] = {
        {MS_STRING, {.buf = {(const uint8_t *)name, len}}},
        {MS_INT, {.i = size}},
    };
    ms_call((ms_fn *)data, args, 2, NULL);
}

void lib_walk(const ms_str *root, ms_fn *visit) {
    walk_entries(ms_str_data(root), ms_str_len(root), each_entry, visit);
}
```

`ms_on_stop(fn, arg)` registers a hook that runs when a stop is requested (SIGINT, SIGTERM, Ctrl-C), from a signal handler or another thread, so it may only do async-signal-safe work, such as setting a flag or calling `uv_async_send`. It lets a native that blocks return; the program then stops with its usual cleanup. `ms_on_stop_remove` removes the hook.

## Linking the native code

`ms build`, `ms run`, and `ms test` take `--link <file>` (repeatable) for an object (`.o`) or static library (`.a`) that defines the symbols. The standard runtime and libc are always linked: on Linux that is the system glibc, or static musl with `--static`; an `extern fn` library built for one does not mix with the other.

```text
cc -c -I crates/ms-rt-abi/include greet.c -o greet.o
ms run main.ms --link greet.o
```

A symbol that no input defines fails the link, and the error names the symbol and suggests `--link`.
