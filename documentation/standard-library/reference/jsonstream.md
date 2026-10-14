+++
title = "jsonstream"
+++

# @std/jsonstream.ms

Import each required symbol with `import Name from "@std/jsonstream.ms"`.

## JsonDecoder {data-api-kind="Interface"}

Decodes a sequence of JSON values from byte chunks of any size.

The decoder buffers only the value being read, so tokens, escapes, and UTF-8 scalars
may be split across chunks. Values may be separated by JSON whitespace or directly
adjacent when they are strings, arrays, or objects, which covers JSON Lines and
concatenated JSON. Top-level numbers, `true`, `false`, and `null` end at whitespace
or at `finish()`. The decoder never reads, closes, or owns a stream.

```manuscript
interface JsonDecoder:
    fn feed(chunk: Bytes) -> Result[List[JsonValue], JsonError]
    fn finish() -> Result[List[JsonValue], JsonError]
```

### JsonDecoder.feed

Adds a chunk and returns every value it completes, in order; the list is empty when
the chunk ends inside a value. An error discards values completed earlier in the same
chunk, and the decoder stays failed and returns that error again. Returns `InvalidInput` after `finish()`.

```manuscript
fn feed(chunk: Bytes) -> Result[List[JsonValue], JsonError]
```

### JsonDecoder.finish

Signals end of input and returns a final unterminated scalar, if any. Input that
ends inside a string, array, or object returns `InvalidData`. The decoder rejects
later calls with `InvalidInput`.

```manuscript
fn finish() -> Result[List[JsonValue], JsonError]
```

## decoder {data-api-kind="Function"}

Creates a decoder. `limits` applies to each value separately: `max_bytes` counts the
value's UTF-8 bytes, `max_depth` its nesting, and `max_values` its parsed values, and
an exceeded limit returns `LimitExceeded`. Omit limits only for trusted input, because
an unterminated value is otherwise buffered without bound. Negative limits return
`InvalidInput`.

```manuscript
fn decoder(limits: Optional[JsonLimits] = none) -> Result[JsonDecoder, JsonError]:
```

