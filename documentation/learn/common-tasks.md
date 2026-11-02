+++
title = "Task recipes"
weight = 5
+++

# Task recipes

Each program is a complete `.ms` file: save it under the shown name and run the command from that directory ([getting started](getting-started.md)). Shell commands assume POSIX; the HTTP recipe needs Python 3 as a local server. `main` returns the exit status.

## Print a line

Save as `hello.ms`. Check both write and flush.

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n"} -->
```manuscript
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    try stdout().write("Hello, Manuscript!\n")
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run hello.ms
```

There is no built-in `print`. `try` propagates I/O errors; `main` returns 1 on failure. Later recipes print no diagnostics; to add one, use `cause.message` ([the Error record](../core-language/errors/results.md#the-error-record)).

## Read command-line arguments

Save as `args.ms`. `arguments()` excludes the executable; values after `--` reach your program.

<!-- manuscript-example: {"mode":"run","args":["Sam","Ada"],"stdout":"Hello, Sam!\nHello, Ada!\n","cases":[{"stdout":""}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    for name in arguments():
        try stdout().write("Hello, {name}!\n")
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run args.ms -- Sam Ada
```

## Parse subcommands and flags

Save as `tool.ms`. `@std/cli.ms` resolves nested commands, typed flags and positional arguments, writes `--help`, and hands your handler a record you define: each field is filled from the flag or argument with the same name (`dry-run` fills `dry_run`). Usage errors print a message and exit with status 2.

<!-- manuscript-example: {"mode":"run","args":["hello","Ada","-n","2"],"stdout":"Hello, Ada!\nHello, Ada!\n"} -->
```manuscript
import Arg, Command, Flag, FlagKind, command from "@std/cli.ms"
import stdout from "@std/io/io.ms"
import arguments from "@std/os/process.ms"

type Greeting:
    name: String
    times: Int

fn greet(options: Greeting) Result[Int, Error]:
    for round in 0..options.times:
        try stdout().write("Hello, {options.name}!\n")
    try stdout().flush()
    return ok(0)

export fn main() Int:
    let hello = command[Greeting](
        name: "hello",
        about: "Print a greeting",
        flags: [Flag("times", FlagKind.Int, "n", "1", "Repeat count")],
        args: [Arg("name", "Who to greet")],
        run: fn options: greet(options)
    )
    return Command(name: "tool", about: "Example tool", children: [hello]).execute(arguments())
```

```sh
ms run tool.ms -- hello Ada -n 2
ms run tool.ms -- hello --help
```

## Read a UTF-8 text file

Save as `read.ms`. `decode_utf8()` returns `none` for invalid UTF-8.

<!-- manuscript-example: {"mode":"run","args":["notes.txt"],"files":{"notes.txt":"hello from a file\n"},"stdout":"hello from a file\n","cases":[{"args":["missing.txt"],"exit_code":1},{"exit_code":1}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import read_file, write_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    let path = try arguments().first().ok_or(Error("missing path", kind: ErrorCategory.InvalidInput))
    let text = try read_file(path, max_bytes: 1048576)
        | .decode_utf8().ok_or(Error("not UTF-8", kind: ErrorCategory.InvalidData))
        | try
    try stdout().write(text)
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
printf 'hello from a file\n' > notes.txt
ms run read.ms -- notes.txt
```

`max_bytes` bounds the read; any failure exits nonzero. There is no `read_text`.

## Write a text file

Save as `write.ms`. `replace: false` fails if the file exists.

<!-- manuscript-example: {"mode":"run","args":["saved.txt"],"want_files":{"saved.txt":"saved notes\n"},"cases":[{"args":["saved.txt"],"files":{"saved.txt":"keep me"},"want_files":{"saved.txt":"keep me"},"exit_code":1},{"exit_code":1}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import read_file, write_file from "@std/os/fs.ms"

fn run() Result[Unit, Error]:
    let path = try arguments().first().ok_or(Error("missing path", kind: ErrorCategory.InvalidInput))
    return write_file(path, "saved notes\n", replace: false)

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run write.ms -- saved.txt
cat saved.txt
```

Use `replace: true` to overwrite. Relative paths use the working directory.

## Read standard input line by line

Save as `lines.ms`. `lines` returns an iterator over the lines; declare it `var` to read `error()` after the loop.

<!-- manuscript-example: {"mode":"run","stdin":"line one\n\nlast line","stdout":"line one\n\nlast line\n","cases":[{"stdout":""}]} -->
```manuscript
import stdin, stdout, lines from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    var reader = lines(stdin(), max_bytes: 4096)
    for line in reader:
        try stdout().write("{line}\n")
    if let failure = reader.error():
        return error(failure)
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
printf 'line one\n\nlast line' | ms run lines.ms
```

An empty line is `""`, and the loop ends at end of input. Line endings are stripped, and the limit applies per line. A read failure or a line over the limit also ends the loop; `error()` is `none` after a clean end. For one line at a time on demand, `read_line` returns `Result[String?, Error]`.

## Parse an integer

Save as `number.ms`. `parse_int()` returns an `Int?`.

<!-- manuscript-example: {"mode":"run","args":["42"],"stdout":"42\n","cases":[{"args":["oops"],"exit_code":1}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

fn show(number: Int) Result[Unit, Error]:
    try stdout().write("{number}\n")
    return stdout().flush()

export fn main() Int:
    let number = arguments().get(0, default: "42").parse_int()
    if let value = number:
        if show(value).is_ok():
            return 0
    return 1
```

```sh
ms run number.ms -- 42
```

Use `get(default)` for a default, or `if let` with a failure path ([Optional values](../core-language/types/optionals.md)).

## Parse JSON

Save as `json.ms`. `parse[String]` errors on malformed JSON or another type.

<!-- manuscript-example: {"mode":"run","args":["\"hello\""],"stdout":"hello\n","cases":[{"args":["{"],"exit_code":1},{"args":["42"],"exit_code":1}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import parse from "@std/data/json.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    let text = try parse[String](arguments().get(0, default: "\"hello\""))
    try stdout().write("{text}\n")
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run json.ms -- '"hello"'
```

Without a type, `parse` returns a `JsonValue` tree for unknown shapes.

## Read and write typed JSON

Save as `config.ms`. Parse a record directly and serialize it back. Use strict encoding so a value with no JSON representation fails instead of being silently omitted.

<!-- manuscript-example: {"mode":"run","args":["{\"name\":\"Sam\"}"],"stdout":"{\"name\":\"Sam\",\"enabled\":true}\n","cases":[{"args":["{\"name\":\"Ada\",\"enabled\":false,\"extra\":1}"],"stdout":"{\"name\":\"Ada\",\"enabled\":false}\n"},{"args":["{}"],"exit_code":1},{"args":["{\"name\":42}"],"exit_code":1}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import parse, stringify from "@std/data/json.ms"
import stdout from "@std/io/io.ms"

type Config:
    name: String
    enabled: Bool = true

fn run() Result[Unit, Error]:
    let text = arguments().get(0, default: "\{\"name\":\"Sam\"\}")
    let config = try parse[Config](text)
    let encoded = try stringify(config, strict: true)
    try stdout().write("{encoded}\n")
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run config.ms -- '{"name":"Sam"}'
```

- A missing `enabled` takes its default; a missing `name` or wrong type is an error.
- Unknown members are ignored unless `ignore_unknown_fields: false`.
- Write `parse[Config]` explicitly after `try`.
- `stringify` writes fields in declaration order. `strict: true` is opt-in; ordinary `stringify` can omit values without a JSON form. Strict mode still omits `none` record fields.

## Make an HTTP GET request

Save as `get.ms`. `fetch` buffers the body, `check_status()` rejects statuses outside 200–299, and `text()` decodes UTF-8.

<!-- manuscript-example: {"mode":"run","args":["$HTTP_URL"],"http":{"status":200,"body":"hello from HTTP\n"},"stdout":"hello from HTTP\n","cases":[{"args":["$HTTP_URL"],"http":{"status":404,"body":"missing"},"exit_code":1},{"args":["invalid URL"],"exit_code":1},{"exit_code":1}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import fetch, FetchOptions from "@std/net/fetch.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    let url = try arguments().first().ok_or(Error("missing URL", kind: ErrorCategory.InvalidInput))
    let response = try fetch(url, FetchOptions(max_response_bytes: 1048576))
    try response.check_status()
    let text = try response.text()
    try stdout().write(text)
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
# In another terminal, serve notes.txt from the current directory:
python3 -m http.server 8000 --bind 127.0.0.1

# In your program's terminal:
ms run get.ms -- http://127.0.0.1:8000/notes.txt
```

The server needs Python 3 and a `notes.txt` (from the file-reading recipe). Transport failures, non-success statuses and invalid UTF-8 exit 1; the body is capped at one mebibyte (1,048,576 bytes). Other `FetchOptions` fields keep their defaults, including the 30-second deadline.

For a JSON response, `try response.json[Config]()` decodes into a type such as the `Config` above. Call `check_status()` first when an error status should fail the operation: `fetch` itself returns error statuses as ordinary responses. For repeated requests, bind a pooled `Fetcher` with `let client = try fetcher()`; see the [fetch API](../standard-library/reference/fetch.md).

Next: [testing](testing.md) and [counting loops](../core-language/control-flow/loops.md#counting-loops).
