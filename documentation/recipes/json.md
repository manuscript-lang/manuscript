+++
title = "Read and validate JSON"
weight = 1
+++

# Read and validate JSON

A configuration file is useful only after the program knows what its values mean. JSON parsing can check both the document's syntax and the shape of the application data. Start with a record when you know that shape; use a `JsonValue` tree when you need to discover it.

This lesson uses [records](../core-language/types/records.md), [optionals](../core-language/types/optionals.md), and [error propagation](../core-language/errors/propagation.md). Follow [getting started](../learn/getting-started.md) to install `ms`.

## Load a configuration record

Create `config.json` in your working directory:

```json
{"name":"Newsletter"}
```

Save the following complete program as `config.ms` beside it:

<!-- manuscript-example: {"mode":"run","files":{"config.json":"{\"name\":\"Newsletter\"}"},"stdout":"{\"name\":\"Newsletter\",\"enabled\":true}\n","cases":[{"files":{"config.json":"{\"name\":\"Newsletter\",\"enabled\":false,\"reply_to\":\"editor@example.com\"}"},"stdout":"{\"name\":\"Newsletter\",\"enabled\":false,\"reply_to\":\"editor@example.com\"}\n"},{"files":{"config.json":"{\"name\":\"Newsletter\",\"enabeld\":false}"},"stdout":"JSON: invalid data: at $: unknown field\n","exit_code":1},{"files":{"config.json":"{\"name\":42}"},"stdout":"JSON: invalid data: at $.name: expected string, found number\n","exit_code":1},{"files":{"config.json":"{}"},"stdout":"JSON: invalid data: at $: missing field \"name\"\n","exit_code":1}]} -->
```manuscript
import parse, stringify, JsonLimits from "@std/data/json.ms"
import read_file from "@std/os/fs.ms"

type Config:
    name: String
    enabled: Bool = true
    reply_to: String?

fn run() Unit!:
    let bytes = try read_file("config.json", max_bytes: 65536).wait()
    let text = try bytes.decode_utf8().ok_or(Error("config must be UTF-8"))
    let config = try parse[Config](
        text,
        limits: JsonLimits(max_depth: 4, max_values: 32),
        ignore_unknown_fields: false
    )
    let normalized = try stringify(config, strict: true)
    print(normalized)
    return ok(unit)

export fn main() Int:
    let outcome = run()
    if let _value = outcome:
        return 0
    print(outcome.err().message)
    return 1
```

Run from that directory:

```sh
ms run config.ms
```

```text
{"name":"Newsletter","enabled":true}
```

The file read returns a promise. `wait()` takes its result, and `try` forwards a read failure from `run`. Decoding bytes checks UTF-8 before parsing JSON. The file limit bounds how much input the read accepts; `JsonLimits` also limits how deeply the parser may nest containers and how many values it may construct. Limits apply before conversion into `Config`.

`parse[Config]` names the type to decode. The compiler knows the fields and their types; this is not an untyped object or a runtime reflection API. After the call succeeds, `config.name` is a `String` and `config.enabled` is a `Bool`. `try` does not supply an expected result type to a generic call, so specify `[Config]` here.

The record describes three different requirements. `name` must be present. `enabled` takes its default when absent. `reply_to` becomes `none` when absent or JSON `null`. Serialization writes fields in declaration order and omits a record field holding `none`, explaining why the output has no `reply_to` member.

## Decide what counts as invalid input

Change the file to include `"enabled":false` or a string `"reply_to"`; the program preserves those values in its output. Change `name` to a number, remove it, or misspell `enabled` as `enabeld`; the program prints its failure message and exits with status 1.

Unknown fields are normally ignored by `parse`. This program sets `ignore_unknown_fields: false` because a misspelled configuration key should not silently take a default. For a response from a service that may add fields independently, accepting unknown fields can be the useful choice. A missing required field or a field with the wrong type still fails either way.

`strict: true` on `stringify` answers a different question: can every value be represented as JSON? It rejects values without a JSON form, such as `Unit`, instead of omitting them or writing `null` in a list. It does not make absent optional record fields appear. Functions and resources cannot satisfy the encoder's `Data` bound in the first place.

The `if let` in `main` handles success; the following statements handle failure: success exits with status 0, while failure prints the actual cause and exits with status 1. For example, setting `name` to `42` reports:

```text
JSON: invalid data: at $.name: expected string, found number
```

The path identifies the field that needs correcting. A larger application can translate the error at this boundary while retaining useful context; see [expected errors](../core-language/errors/results.md). Do not replace parsing failures with an empty configuration unless that is an explicit application policy.

## Inspect a document with an unknown shape

Some inputs contain data whose structure is decided elsewhere. Without a type argument, `parse` produces a `JsonValue`: a fixed enum of null, booleans, numbers, strings, arrays, and objects. Accessors return optionals because both a missing member and an unexpected shape are possible.

Save this complete program as `inspect.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada\n9007199254740993\n"} -->
```manuscript
import parse, stringify from "@std/data/json.ms"

fn run() Unit!:
    let document = try parse("\{\"user\":\{\"name\":\"Ada\"\},\"id\":9007199254740993\}")
    let selected = document.get_in(["user", "name"])
    let name = try selected.ok_or(Error("missing user name"))
    let text = try name.as_string().ok_or(Error("user name must be text"))
    print(text)
    let id = try document.get("id").ok_or(Error("missing id"))
    print(try stringify(id))
    return ok(unit)

export fn main() Int:
    let outcome = run()
    if let _value = outcome:
        return 0
    print(outcome.err().message)
    return 1
```

```sh
ms run inspect.ms
```

```text
Ada
9007199254740993
```

`get_in` follows object members without a chain of nested branches. It lends the selected value from the document, so keep the document alive and unchanged while using that selection. `as_string` returns an owned copy. `as_list` and `as_map` likewise clone their payloads; they are useful for processing a separate collection, but are not mutable views into the document.

Numbers in `JsonValue` retain their original token text. Re-encoding the selected `id` therefore preserves all its digits without first converting it to floating point. Use `as_int` when you require an integer that fits `Int`; a fraction, exponent spelling, or out-of-range value returns `none`. Use `as_float` when a finite floating-point value is the intended representation.

## Choose the boundary deliberately

Use typed decoding for data your application defines, and document decoding for exploratory or variable data. Neither choice removes the need for domain checks: a field of type `Int` can still hold a negative quantity unless your code rejects it.

JSON also does not preserve every distinction in Manuscript values. For example, nested optionals can distinguish absence from a present `none`, but decoding JSON `null` produces absence. A custom `JsonEncode` implementation changes serialization; typed decoding does not automatically invert that custom format. See the [JSON API](../standard-library/reference/data/json.ms.md) for these encoding rules, enum representations, streaming readers, and limits.

Next, use typed data to [render a template](templates.md).
