+++
title = "Common tasks"
weight = 3
+++

# Common tasks

Each program below is a complete `.ms` file. Use a current `ms` build, save the code under the shown filename, and run the command from that directory. These examples use the current [optional argument-label rules](../core-language/functions/declarations-and-calls.md#argument-names); older compilers may require explicit labels. Follow [getting started](getting-started.md) to install or build the CLI.

The shell commands assume a POSIX shell; in PowerShell, create the same input files or pipe the same text using its commands. The HTTP recipe additionally uses Python 3 as a local server. Imports name the standard APIs used, and `main` returns the process exit status.

## Print a line

Import `stdout` from `@std/io.ms`, convert text to bytes, and check both writing and flushing. Save this program as `hello.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n"} -->
```manuscript
import stdout from "@std/io.ms"

fn run() -> Result[Unit, Error]:
    try stdout().write("Hello, Manuscript!\n".to_bytes())
    return stdout().flush()

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

```sh
ms run hello.ms
```

There is no built-in `print` or `println`. `try` propagates an I/O error to `run`'s caller; `main` returns exit status 1 on failure. It returns 0 only after the write and flush succeed. The recipes below use this same exit-status convention and do not print error diagnostics. To include a diagnostic, handle the error with `cause.message()` and check any write to `stderr` too; see [expected errors](../core-language/errors/results.md#a-common-error-boundary).

## Read command-line arguments

Save as `args.ms`. `arguments()` excludes the executable path; the CLI passes values after `--` to your program.

<!-- manuscript-example: {"mode":"run","args":["Sam","Ada"],"stdout":"Hello, Sam!\nHello, Ada!\n","cases":[{"stdout":""}]} -->
```manuscript
import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

fn run() -> Result[Unit, Error]:
    for name in arguments():
        try stdout().write("Hello, {name}!\n".to_bytes())
    return stdout().flush()

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

```sh
ms run args.ms -- Sam Ada
```

## Read a UTF-8 text file

Save as `read.ms`. The path comes from the first argument. `read_file` returns bytes; `to_text()` returns `none` when they are not valid UTF-8.

<!-- manuscript-example: {"mode":"run","args":["notes.txt"],"files":{"notes.txt":"hello from a file\n"},"stdout":"hello from a file\n","cases":[{"args":["missing.txt"],"exit_code":1},{"exit_code":1}]} -->
```manuscript
import arguments from "@std/cli.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import stdout from "@std/io.ms"

fn run() -> Result[Unit, Error]:
    let path = arguments().at(0)
    if path.is_none():
        return error(FileSystemError.InvalidInput)
    let bytes = try filesystem().read_file(path.unwrap(), max_bytes: 1048576)
    let text = bytes.to_text()
    if text.is_none():
        return error(FileSystemError.InvalidData)
    try stdout().write(text.unwrap().to_bytes())
    return stdout().flush()

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

```sh
printf 'hello from a file\n' > notes.txt
ms run read.ms -- notes.txt
```

The one-megabyte limit bounds the read. Missing arguments, filesystem errors, invalid text, and output errors produce a nonzero exit status. There is no `filesystem().read_text` method.

## Write a text file

Save as `write.ms`. `replace: false` creates a new file and reports an error if the destination already exists.

<!-- manuscript-example: {"mode":"run","args":["saved.txt"],"want_files":{"saved.txt":"saved notes\n"},"cases":[{"args":["saved.txt"],"files":{"saved.txt":"keep me"},"want_files":{"saved.txt":"keep me"},"exit_code":1},{"exit_code":1}]} -->
```manuscript
import arguments from "@std/cli.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"

fn run() -> Result[Unit, Error]:
    let path = arguments().at(0)
    if path.is_none():
        return error(FileSystemError.InvalidInput)
    return filesystem().write_file(path.unwrap(), "saved notes\n".to_bytes(), replace: false)

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

```sh
ms run write.ms -- saved.txt
cat saved.txt
```

Use `replace: true` when overwriting is intended. Relative paths resolve from the process working directory.

## Read standard input line by line

Save as `lines.ms`. Unwrap the outer `Result` with `try`, then check the inner `Optional` for EOF before extracting the line.

<!-- manuscript-example: {"mode":"run","stdin":"line one\n\nlast line","stdout":"line one\n\nlast line\n","cases":[{"stdout":""}]} -->
```manuscript
import {stdin, stdout, read_line} from "@std/io.ms"

fn run() -> Result[Unit, Error]:
    let input = stdin()
    while true:
        let line = try read_line(input, max_bytes: 4096)
        if line.is_none():
            break
        try stdout().write("{line.unwrap()}\n".to_bytes())
    return stdout().flush()

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

```sh
printf 'line one\n\nlast line' | ms run lines.ms
```

`some("")` is an empty line; `none` is EOF. `read_line` removes the line ending, and this program adds one when writing each line. The limit bounds a line; it does not limit the total number of lines. Do not interpolate the Optional itself when you want its text.

## Parse an integer

Save as `number.ms`. `parse_int()` returns an `Optional[Int]`, so invalid input must be handled before using the number.

<!-- manuscript-example: {"mode":"run","args":["42"],"stdout":"42\n","cases":[{"args":["oops"],"exit_code":1}]} -->
```manuscript
import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

fn show(number: Int) -> Result[Unit, Error]:
    try stdout().write("{number}\n".to_bytes())
    return stdout().flush()

export fn main() -> Int:
    let number = arguments().at(0).unwrap_or("42").parse_int()
    if number.is_none():
        return 1
    match show(number.unwrap()):
        ok(_): return 0
        error(_): return 1
```

```sh
ms run number.ms -- 42
```

Use `unwrap_or` when absence has a sensible default; use `is_none` and a failure path when invalid input should stop the task. See [Optional values](../core-language/types/optionals.md).

## Parse JSON

Save as `json.ms`. This task accepts a JSON string and writes the decoded text. `parse` can also return objects, arrays, numbers, booleans, or null; this program rejects those shapes explicitly.

<!-- manuscript-example: {"mode":"run","args":["\"hello\""],"stdout":"hello\n","cases":[{"args":["{"],"exit_code":1},{"args":["42"],"exit_code":1}]} -->
```manuscript
import arguments from "@std/cli.ms"
import {parse, JsonError} from "@std/json.ms"
import stdout from "@std/io.ms"

fn run() -> Result[Unit, Error]:
    let value = try parse(arguments().at(0).unwrap_or("\"hello\""))
    let text = match value:
        StringValue(text): text
        _: return error(JsonError.InvalidData)
    try stdout().write("{text}\n".to_bytes())
    return stdout().flush()

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

```sh
ms run json.ms -- '"hello"'
```

The parse error and a valid value with the wrong shape are separate checks. See [JSON declarations](../standard-library/reference/json.md) for the other `JsonValue` cases and optional parsing limits.

## Make an HTTP GET request

Save as `get.ms`. Import `network` from `@std/net.ms`; the buffered response has `status` and `body` fields. This task requires a 200 response containing UTF-8 text.

<!-- manuscript-example: {"mode":"run","args":["$HTTP_URL"],"http":{"status":200,"body":"hello from HTTP\n"},"stdout":"hello from HTTP\n","cases":[{"args":["$HTTP_URL"],"http":{"status":404,"body":"missing"},"exit_code":1},{"args":["invalid URL"],"exit_code":1},{"exit_code":1}]} -->
```manuscript
import arguments from "@std/cli.ms"
import Map from "@std/collections.ms"
import HttpError from "@std/http.ms"
import network from "@std/net.ms"
import stdout from "@std/io.ms"

fn run() -> Result[Unit, Error]:
    let url = arguments().at(0)
    if url.is_none():
        return error(HttpError.InvalidInput)
    let response = try network().request(
        "GET", url.unwrap(), Map[String, String](), "".to_bytes(),
        max_response_bytes: 1048576
    )
    if response.status != 200:
        return error(HttpError.InvalidData)
    let text = response.body.to_text()
    if text.is_none():
        return error(HttpError.InvalidData)
    try stdout().write(text.unwrap().to_bytes())
    return stdout().flush()

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

```sh
# In another terminal, serve notes.txt from the current directory:
python3 -m http.server 8000 --bind 127.0.0.1

# In your program's terminal:
ms run get.ms -- http://127.0.0.1:8000/notes.txt
```

The local-server command needs Python 3 and a `notes.txt` file, such as the one created in the file-reading recipe. Transport failures and non-200 statuses produce exit status 1. The response body is buffered with a one-megabyte limit. For streaming and timeouts, see [HTTP](../standard-library/http.md).

## Start and join a task

Save as `task.ms`. `TaskGroup.start` returns a typed handle; `join` waits for that task and returns its result or an execution error.

<!-- manuscript-example: {"mode":"run","stdout":"42\n"} -->
```manuscript
import TaskGroup from "@std/tasks.ms"
import stdout from "@std/io.ms"

fn run() -> Result[Unit, Error]:
    with group = TaskGroup():
        let task = group.start(fn() -> Int:
            return 6 * 7
        )
        let answer = try task.join()
        try stdout().write("{answer}\n".to_bytes())
        try stdout().flush()
    return ok(unit)

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

```sh
ms run task.ms
```

`with` closes the group and joins its child work on every exit, including a failed join or write. Keep resources needed by a task open until it finishes. See [task groups](../concurrency/task-groups.md).

For a tests file and an assertion helper, continue with [testing](testing.md). For counting iterations, see [counting loops](../core-language/control-flow/loops.md#counting-loops).
