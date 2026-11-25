+++
title = "Numbers and JSON"
weight = 6
+++

# Numbers and JSON

Parse integers and JSON, and read and write typed JSON. Each program is a complete `.ms` file: save it under the shown name and run the command from that directory ([getting started](../learn/getting-started.md)). `main` returns the exit status.

## Parse an integer

Save as `number.ms`. `parse_int()` returns an `Int?`.

<!-- manuscript-example: {"mode":"run","args":["42"],"stdout":"42\n","cases":[{"args":["oops"],"exit_code":1}]} -->
```manuscript
import (
    stdout from "@std/io/io.ms",
    arguments from "@std/os/env.ms",
)

fn show(number Int) Result[Void, Error] {
    stdout().write(f"{number}\n")?
    return stdout().flush()
}

fn main() Int {
    number := arguments().get_or(0, "42").parse_int()
    if number != null and show(number).is_ok() { return 0 }
    return 1
}
```

```sh
ms run number.ms -- 42
```

```text
42
```

Use `x or default` for a default, or compare with `null` and take a failure path ([Optional values](../core-language/types/optionals.md)).

## Parse JSON

Save as `json.ms`. `parse[String]` errors on malformed JSON or another type.

<!-- manuscript-example: {"mode":"run","args":["\"hello\""],"stdout":"hello\n","cases":[{"args":["{"],"exit_code":1},{"args":["42"],"exit_code":1}]} -->
```manuscript
import (
    parse from "@std/data/json.ms",
    stdout from "@std/io/io.ms",
    arguments from "@std/os/env.ms",
)

fn run() Result[Void, Error] {
    text := parse[String](arguments().get_or(0, "\"hello\""))?
    stdout().write(f"{text}\n")?
    return stdout().flush()
}

fn main() Void! {
    return run()
}
```

```sh
ms run json.ms -- '"hello"'
```

```text
hello
```

Without a type, `parse` returns a `JsonValue` tree for unknown shapes.

<span id="let-types-describe-your-data"></span>

## Read and write typed JSON

Save as `config.ms`. Parse into a type directly and serialize it back. Use strict encoding so a value with no JSON representation fails instead of being silently omitted.

<!-- manuscript-example: {"mode":"run","args":["{\"name\":\"Sam\"}"],"stdout":"{\"name\":\"Sam\",\"enabled\":true}\n","cases":[{"args":["{\"name\":\"Ada\",\"enabled\":false,\"extra\":1}"],"stdout":"{\"name\":\"Ada\",\"enabled\":false}\n"},{"args":["{}"],"exit_code":1},{"args":["{\"name\":42}"],"exit_code":1}]} -->
```manuscript
import (
    StringifyOptions, parse, stringify from "@std/data/json.ms",
    stdout from "@std/io/io.ms",
    arguments from "@std/os/env.ms",
)

type Config {
    name String
    enabled Bool = true
}

fn run() Result[Void, Error] {
    text := arguments().get_or(0, "{\"name\":\"Sam\"}")
    config := parse[Config](text)?
    encoded := stringify(config, StringifyOptions(strict: true))?
    stdout().write(f"{encoded}\n")?
    return stdout().flush()
}

fn main() Void! {
    return run()
}
```

```sh
ms run config.ms -- '{"name":"Sam"}'
```

```text
{"name":"Sam","enabled":true}
```

- A missing `enabled` takes its default; a missing `name` or wrong type is an error.
- Unknown members are ignored unless `JsonOptions(ignore_unknown_fields: false)`.
- Write the type argument explicitly: `parse[Config](text)?`.
- `stringify` writes fields in declaration order. `StringifyOptions(strict: true)` is opt-in; ordinary `stringify` can omit values without a JSON form. Strict mode still omits `null` fields.
