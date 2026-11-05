+++
title = "Strings and bytes"
weight = 4
+++

# Strings and bytes

Review text boundaries and explicit conversions before passing strings to files, protocols or users; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::text and interpolation\nPASS example.ms::text and interpolation\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "text and interpolation":
    let name = "Ada"
    let greeting = """
        Hello, {name}!
        Welcome.
        """
    try expect_equal(greeting, "Hello, Ada!\nWelcome.")
    try expect_equal("\{name\}".contains(name), false)
    let count = 3
    let convert: fn() String = count.to_string
    try expect_equal(convert(), "3")
```

```sh
ms test example.ms
```

```text
RUN example.ms::text and interpolation
PASS example.ms::text and interpolation
1 tests, 0 failed
```

- Strings are immutable UTF-8; interpolation converts each expression once, left to right.
- Triple-quoted text removes closing indentation; prefix it with `r` for literal braces and backslashes.

## Half-open slices

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::unicode slices\nPASS example.ms::unicode slices\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "unicode slices":
    let text = "aé🙂z"
    try expect_equal(text.length(), 4)
    try expect_equal(text.byte_length(), 8)
    try expect_equal(try text.slice(start: -2, end: 4), "🙂z")
    try expect_equal(text.index_of("é"), 1)
    try expect_equal("a\r\nb\n".lines(), ["a", "b"])
```

```sh
ms test example.ms
```

```text
RUN example.ms::unicode slices
PASS example.ms::unicode slices
1 tests, 0 failed
```

## Encoding and parsing

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::utf8 and parsing\nPASS example.ms::utf8 and parsing\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import Bytes from "@std/bytes.ms"
import expect_equal from "@std/test/test.ms"

test "utf8 and parsing":
    try expect_equal("é".to_bytes().decode_utf8(), "é")
    let invalid: String? = none
    try expect_equal(Bytes([255]).decode_utf8(), invalid)
    if let count = "-007".parse_int():
        try expect_equal(count, -7)
    else:
        try expect_equal(false, true)
```

```sh
ms test example.ms
```

```text
RUN example.ms::utf8 and parsing
PASS example.ms::utf8 and parsing
1 tests, 0 failed
```

## Padding and fixed digits

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::padded amount\nPASS example.ms::padded amount\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "padded amount":
    let amount = 3.14159.to_fixed(2)
    try expect_equal("total".pad_end(8, " ") + amount.pad_start(8, " "), "total       3.14")
```

```sh
ms test example.ms
```

```text
RUN example.ms::padded amount
PASS example.ms::padded amount
1 tests, 0 failed
```

## Binary data

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::binary codecs\nPASS example.ms::binary codecs\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import BytesBuilder from "@std/bytes.ms"
import expect_equal from "@std/test/test.ms"

test "binary codecs":
    var out = BytesBuilder()
    out.append_uint16_be(258)
    out.append_float64_le(1.5)
    let data = out.build()
    try expect_equal(try data.uint16_be(0), 258)
    try expect_equal(try data.float64_le(2), 1.5)
```

```sh
ms test example.ms
```

```text
RUN example.ms::binary codecs
PASS example.ms::binary codecs
1 tests, 0 failed
```

<span id="string-literals"></span><span id="multi-line-and-raw-literals"></span><span id="interpolation"></span><span id="converting-values-to-string"></span><span id="indexing-and-character-boundaries"></span><span id="replacing-text"></span><span id="deterministic-formatting"></span>

Next: [String methods](../../standard-library/reference/prelude.md#string) and [Bytes methods](../../standard-library/reference/bytes.ms.md); [Numbers](numbers-and-booleans.md) · [Bytes reference](../../standard-library/reference/bytes.ms.md).
