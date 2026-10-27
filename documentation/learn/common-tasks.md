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
from "@std/io.ms" import stdout

def run() -> Result[Unit, Error]:
    try stdout().write("Hello, Manuscript!\n")
    return stdout().flush()

export def main() -> Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run hello.ms
```

There is no built-in `print`. `try` propagates I/O errors; `main` returns 1 on failure. Later recipes print no diagnostics; to add one, use `cause.message()` ([error boundary](../core-language/errors/results.md#a-common-error-boundary)).

## Read command-line arguments

Save as `args.ms`. `arguments()` excludes the executable; values after `--` reach your program.

<!-- manuscript-example: {"mode":"run","args":["Sam","Ada"],"stdout":"Hello, Sam!\nHello, Ada!\n","cases":[{"stdout":""}]} -->
```manuscript
from "@std/process.ms" import arguments
from "@std/io.ms" import stdout

def run() -> Result[Unit, Error]:
    for name in arguments():
        try stdout().write(f"Hello, {name}!\n")
    return stdout().flush()

export def main() -> Int:
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
from "@std/cli.ms" import Arg, Command, Flag, FlagKind, command
from "@std/io.ms" import stdout
from "@std/process.ms" import arguments

type Greeting:
    name: String
    times: Int

def greet(options: Greeting) -> Result[Int, Error]:
    for round in 0..options.times:
        try stdout().write(f"Hello, {options.name}!\n")
    try stdout().flush()
    return ok(0)

export def main() -> Int:
    let hello = command[Greeting](
        name: "hello",
        about: "Print a greeting",
        flags: [Flag("times", FlagKind.Int, "n", "1", "Repeat count")],
        args: [Arg("name", "Who to greet")],
        run: lambda options: greet(options)
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
from "@std/process.ms" import arguments
from "@std/fs.ms" import filesystem, FileSystemError
from "@std/io.ms" import stdout

def run() -> Result[Unit, Error]:
    let path = try arguments().first().ok_or(FileSystemError.InvalidInput)
    let text = try filesystem().read_file(path, max_bytes: 1048576)
        | .decode_utf8().ok_or(FileSystemError.InvalidData)
        | try
    try stdout().write(text)
    return stdout().flush()

export def main() -> Int:
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

Save as `write.ms`. `replace: False` fails if the file exists.

<!-- manuscript-example: {"mode":"run","args":["saved.txt"],"want_files":{"saved.txt":"saved notes\n"},"cases":[{"args":["saved.txt"],"files":{"saved.txt":"keep me"},"want_files":{"saved.txt":"keep me"},"exit_code":1},{"exit_code":1}]} -->
```manuscript
from "@std/process.ms" import arguments
from "@std/fs.ms" import filesystem, FileSystemError

def run() -> Result[Unit, Error]:
    let path = try arguments().first().ok_or(FileSystemError.InvalidInput)
    return filesystem().write_file(path, "saved notes\n", replace: False)

export def main() -> Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run write.ms -- saved.txt
cat saved.txt
```

Use `replace: True` to overwrite. Relative paths use the working directory.

## Read standard input line by line

Save as `lines.ms`. `lines` returns an iterator over the lines; declare it `var` to read `error()` after the loop.

<!-- manuscript-example: {"mode":"run","stdin":"line one\n\nlast line","stdout":"line one\n\nlast line\n","cases":[{"stdout":""}]} -->
```manuscript
from "@std/io.ms" import stdin, stdout, lines

def run() -> Result[Unit, Error]:
    var reader = lines(stdin(), max_bytes: 4096)
    for line in reader:
        try stdout().write(f"{line}\n")
    if let failure = reader.error():
        return error(failure)
    return stdout().flush()

export def main() -> Int:
    if run().is_error():
        return 1
    return 0
```

```sh
printf 'line one\n\nlast line' | ms run lines.ms
```

An empty line is `""`, and the loop ends at end of input. Line endings are stripped, and the limit applies per line. A read failure or a line over the limit also ends the loop; `error()` is `none` after a clean end. For one line at a time on demand, `read_line` returns `Result[Optional[String], IoError]`.

## Parse an integer

Save as `number.ms`. `parse_int()` returns an `Optional[Int]`.

<!-- manuscript-example: {"mode":"run","args":["42"],"stdout":"42\n","cases":[{"args":["oops"],"exit_code":1}]} -->
```manuscript
from "@std/process.ms" import arguments
from "@std/io.ms" import stdout

def show(number: Int) -> Result[Unit, Error]:
    try stdout().write(f"{number}\n")
    return stdout().flush()

export def main() -> Int:
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
from "@std/process.ms" import arguments
from "@std/json.ms" import parse
from "@std/io.ms" import stdout

def run() -> Result[Unit, Error]:
    let text = try parse[String](arguments().get(0, default: "\"hello\""))
    try stdout().write(f"{text}\n")
    return stdout().flush()

export def main() -> Int:
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
from "@std/process.ms" import arguments
from "@std/json.ms" import parse, stringify
from "@std/io.ms" import stdout

type Config:
    name: String
    enabled: Bool = True

def run() -> Result[Unit, Error]:
    let text = arguments().get(0, default: "{\"name\":\"Sam\"}")
    let config = try parse[Config](text)
    let encoded = try stringify(config, strict: True)
    try stdout().write(f"{encoded}\n")
    return stdout().flush()

export def main() -> Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run config.ms -- '{"name":"Sam"}'
```

- A missing `enabled` takes its default; a missing `name` or wrong type is an error.
- Unknown members are ignored unless `ignore_unknown_fields: False`.
- Write `parse[Config]` explicitly after `try`.
- `stringify` writes fields in declaration order. `strict: True` is opt-in; ordinary `stringify` can omit values without a JSON form. Strict mode still omits `none` record fields.

## Make an HTTP GET request

Save as `get.ms`. `fetch` buffers the body, `check_status()` rejects statuses outside 200–299, and `text()` decodes UTF-8.

<!-- manuscript-example: {"mode":"run","args":["$HTTP_URL"],"http":{"status":200,"body":"hello from HTTP\n"},"stdout":"hello from HTTP\n","cases":[{"args":["$HTTP_URL"],"http":{"status":404,"body":"missing"},"exit_code":1},{"args":["invalid URL"],"exit_code":1},{"exit_code":1}]} -->
```manuscript
from "@std/process.ms" import arguments
from "@std/fetch.ms" import fetch, FetchOptions
from "@std/http.ms" import HttpError
from "@std/io.ms" import stdout

def run() -> Result[Unit, Error]:
    let url = try arguments().first().ok_or(HttpError.InvalidInput)
    let response = try fetch(url, FetchOptions(max_response_bytes: 1048576))
    try response.check_status()
    let text = try response.text()
    try stdout().write(text)
    return stdout().flush()

export def main() -> Int:
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

For a JSON response, `try response.json[Config]()` decodes into a type such as the `Config` above. Call `check_status()` first when an error status should fail the operation: `fetch` itself returns error statuses as ordinary responses. For repeated requests, open a pooled `Fetcher` with `with let client = try fetcher():`; see the [fetch API](../standard-library/reference/fetch.md).

Next: [testing](testing.md) and [counting loops](../core-language/control-flow/loops.md#counting-loops).
