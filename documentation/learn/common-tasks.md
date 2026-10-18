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
import stdout from "@std/io.ms"

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

There is no built-in `print`. `try` propagates I/O errors; `main` returns 1 on failure. Later recipes print no diagnostics; to add one, use `cause.message()` ([error boundary](../core-language/errors/results.md#a-common-error-boundary)).

## Read command-line arguments

Save as `args.ms`. `arguments()` excludes the executable; values after `--` reach your program.

<!-- manuscript-example: {"mode":"run","args":["Sam","Ada"],"stdout":"Hello, Sam!\nHello, Ada!\n","cases":[{"stdout":""}]} -->
```manuscript
import arguments from "@std/process.ms"
import stdout from "@std/io.ms"

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

## Read a UTF-8 text file

Save as `read.ms`. `to_string()` returns `none` for invalid UTF-8.

<!-- manuscript-example: {"mode":"run","args":["notes.txt"],"files":{"notes.txt":"hello from a file\n"},"stdout":"hello from a file\n","cases":[{"args":["missing.txt"],"exit_code":1},{"exit_code":1}]} -->
```manuscript
import arguments from "@std/process.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import stdout from "@std/io.ms"

fn run() Result[Unit, Error]:
    let path = try arguments().at(0).ok_or(FileSystemError.InvalidInput)
    let text = try filesystem().read_file(path, max_bytes: 1048576)
        | .decode_utf8().ok_or(FileSystemError.InvalidData)
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
import arguments from "@std/process.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"

fn run() Result[Unit, Error]:
    let path = try arguments().at(0).ok_or(FileSystemError.InvalidInput)
    return filesystem().write_file(path, "saved notes\n", replace: false)

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

Save as `lines.ms`. `try` the `Result`, then check the `Optional` for EOF.

<!-- manuscript-example: {"mode":"run","stdin":"line one\n\nlast line","stdout":"line one\n\nlast line\n","cases":[{"stdout":""}]} -->
```manuscript
import {stdin, stdout, read_line} from "@std/io.ms"

fn run() Result[Unit, Error]:
    let input = stdin()
    while true:
        let line = try read_line(input, max_bytes: 4096)
        if let text = line:
            try stdout().write("{text}\n")
        else:
            break
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
printf 'line one\n\nlast line' | ms run lines.ms
```

`some("")` is an empty line; `none` is EOF. `read_line` strips the line ending, and the limit applies per line.

## Parse an integer

Save as `number.ms`. `parse_int()` returns an `Optional[Int]`.

<!-- manuscript-example: {"mode":"run","args":["42"],"stdout":"42\n","cases":[{"args":["oops"],"exit_code":1}]} -->
```manuscript
import arguments from "@std/process.ms"
import stdout from "@std/io.ms"

fn show(number: Int) Result[Unit, Error]:
    try stdout().write("{number}\n")
    return stdout().flush()

export fn main() Int:
    let number = arguments().at(0).get("42").parse_int()
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
import arguments from "@std/process.ms"
import parse from "@std/json.ms"
import stdout from "@std/io.ms"

fn run() Result[Unit, Error]:
    let text = try parse[String](arguments().at(0).get("\"hello\""))
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

Save as `config.ms`. Parse a record directly and serialize it back.

<!-- manuscript-example: {"mode":"run","args":["{\"name\":\"Sam\"}"],"stdout":"{\"name\":\"Sam\",\"enabled\":true}\n","cases":[{"args":["{\"name\":\"Ada\",\"enabled\":false,\"extra\":1}"],"stdout":"{\"name\":\"Ada\",\"enabled\":false}\n"},{"args":["{}"],"exit_code":1},{"args":["{\"name\":42}"],"exit_code":1}]} -->
```manuscript
import arguments from "@std/process.ms"
import {parse, stringify} from "@std/json.ms"
import stdout from "@std/io.ms"

type Config:
    name: String
    enabled: Bool = true

fn run() Result[Unit, Error]:
    let text = arguments().at(0).get("\{\"name\":\"Sam\"\}")
    let encoded = try parse[Config](text)
        | try stringify
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
- `stringify` writes fields in declaration order.

## Make an HTTP GET request

Save as `get.ms`. Status is `response.metadata().status`; bytes are `response.body`. This requires a 200 UTF-8 response.

<!-- manuscript-example: {"mode":"run","args":["$HTTP_URL"],"http":{"status":200,"body":"hello from HTTP\n"},"stdout":"hello from HTTP\n","cases":[{"args":["$HTTP_URL"],"http":{"status":404,"body":"missing"},"exit_code":1},{"args":["invalid URL"],"exit_code":1},{"exit_code":1}]} -->
```manuscript
import arguments from "@std/process.ms"
import {HttpError, HttpMethod, headers} from "@std/http.ms"
import network from "@std/net.ms"
import stdout from "@std/io.ms"

fn run() Result[Unit, Error]:
    let url = try arguments().at(0).ok_or(HttpError.InvalidInput)
    let response = try network().request(
        HttpMethod.Get, url, headers(), "",
        max_response_bytes: 1048576
    )
    if response.metadata().status != 200:
        return error(HttpError.InvalidData)
    let text = try response.body.decode_utf8().ok_or(HttpError.InvalidData)
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

The server needs Python 3 and a `notes.txt` (from the file-reading recipe). Transport failures and non-200 statuses exit 1; the body is capped at one megabyte.

## Start and join a task

Save as `task.ms`. `TaskGroup.start` returns a handle; `join` returns its result.

<!-- manuscript-example: {"mode":"run","stdout":"42\n"} -->
```manuscript
import TaskGroup from "@std/tasks.ms"
import stdout from "@std/io.ms"

fn run() Result[Unit, Error]:
    with group = TaskGroup():
        let task = group.start(fn() Int:
            return 6 * 7
        )
        let answer = try task.join()
        try stdout().write("{answer}\n")
        try stdout().flush()
    return ok(unit)

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run task.ms
```

`with` joins child work on every exit. Keep resources a task needs open until it finishes.

Next: [testing](testing.md) and [counting loops](../core-language/control-flow/loops.md#counting-loops).
