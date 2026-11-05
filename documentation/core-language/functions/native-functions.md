+++
title = "Native functions"
weight = 3
+++

# Native functions

An explicit native boundary lets reviewers check which external symbol and ownership contract a call uses; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::call a linked native symbol\nPASS example.ms::call a linked native symbol\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

extern fn llabs(value: Int) Int

fn magnitude(value: Int) Int:
    return llabs(value)

test "call a linked native symbol":
    try expect_equal(magnitude(-7), 7)
```

```sh
ms test example.ms
```

```text
RUN example.ms::call a linked native symbol
PASS example.ms::call a linked native symbol
1 tests, 0 failed
```

- Native arguments are borrowed during the call; retained values need the ABI ownership operation.
- This alpha API requires exact native signatures; [the ABI header](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-rt-abi/include/ms_abi.h) defines representation and lifetime operations.

<span id="types-that-cross"></span><span id="errors"></span><span id="extern-types"></span><span id="calling-back-into-manuscript"></span><span id="linking-the-native-code"></span>

Next: [accepted native signatures](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/src/checker.rs#L1476); [native build setup](../../developer-tooling/how-it-works.md).
