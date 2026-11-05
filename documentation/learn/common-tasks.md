+++
title = "Task recipes"
weight = 4
aliases = ["/learn/best-practices/"]
+++

# Task recipes

Each program is a complete `.ms` file: save it under the shown name and run the command from that directory ([getting started](getting-started.md)). Shell commands assume POSIX; the HTTP recipe needs Python 3 as a local server. `main` returns the exit status.

## Print a line

Save as `hello.ms`. `print` is available without an import and adds a newline.

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n"} -->
```manuscript
export fn main() Int:
    print("Hello, Manuscript!")
    return 0
```

```sh
ms run hello.ms
```

```text
Hello, Manuscript!
```

`print` returns `Unit`. The next recipe uses `stdout().write(...)` and `stdout().flush().wait()` to control text and flushing explicitly. These methods use the stream `Result` interface, but ordinary stdout does not expose native write errors through it. Use `stdout_bytes()` for byte output.

## Read command-line arguments

Save as `args.ms`. `arguments()` excludes the executable; values after `--` reach your program.

<!-- manuscript-example: {"mode":"run","args":["Sam","Ada"],"stdout":"Hello, Sam!\nHello, Ada!\n","cases":[{"stdout":""}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

fn run() Unit!:
    for name in arguments():
        try stdout().write("Hello, {name}!\n")
    return stdout().flush().wait()

export fn main() Int:
    let outcome = run()
    if let _completed = outcome:
        return 0
    print(outcome.err().message)
    return 1
```

```sh
ms run args.ms -- Sam Ada
```

```text
Hello, Sam!
Hello, Ada!
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

fn greet(options: Greeting) Int!:
    for round in 0..options.times:
        try stdout().write("Hello, {options.name}!\n")
    try stdout().flush().wait()
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
```

```text
Hello, Ada!
Hello, Ada!
```

Run `ms run tool.ms -- hello --help` to see the command’s arguments and flags.

## Read a UTF-8 text file

Save as `read.ms`. `decode_utf8()` returns `none` for invalid UTF-8.

<!-- manuscript-example: {"mode":"run","args":["notes.txt"],"files":{"notes.txt":"hello from a file\n"},"stdout":"hello from a file\n","cases":[{"args":["missing.txt"],"exit_code":1,"stdout":"filesystem: file or directory not found: missing.txt\n"},{"exit_code":1,"stdout":"missing path\n"}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import read_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"

fn run() Unit!:
    let path = try arguments().first().ok_or(Error("missing path", kind: "EINVAL"))
    let text = try read_file(path, max_bytes: 1048576).wait()
        | .decode_utf8().ok_or(Error("not UTF-8", kind: "EBADMSG"))
        | try
    try stdout().write(text)
    return stdout().flush().wait()

export fn main() Int:
    let outcome = run()
    if let _completed = outcome:
        return 0
    print(outcome.err().message)
    return 1
```

```sh
printf 'hello from a file\n' > notes.txt
ms run read.ms -- notes.txt
```

```text
hello from a file
```

`max_bytes` bounds the read. On failure the program prints the error message and exits nonzero.

## Write a text file

Save as `write.ms`. `replace: false` fails if the file exists.

<!-- manuscript-example: {"mode":"run","args":["saved.txt"],"want_files":{"saved.txt":"saved notes\n"},"cases":[{"args":["saved.txt"],"files":{"saved.txt":"keep me"},"want_files":{"saved.txt":"keep me"},"exit_code":1,"stdout":"filesystem: already exists: saved.txt\n"},{"exit_code":1,"stdout":"missing path\n"}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import write_file from "@std/os/fs.ms"

fn run() Unit!:
    let path = try arguments().first().ok_or(Error("missing path", kind: "EINVAL"))
    return write_file(path, "saved notes\n", replace: false).wait()

export fn main() Int:
    let outcome = run()
    if let _completed = outcome:
        return 0
    print(outcome.err().message)
    return 1
```

```sh
ms run write.ms -- saved.txt
cat saved.txt
```

```text
saved notes
```

The program succeeds silently; `cat` shows the saved content. On failure it prints the error message and exits with status 1. Use `replace: true` to overwrite. Relative paths use the working directory.

## Read standard input line by line

Save as `lines.ms`. `lines` wraps a byte stream as a stream of lines; `read().wait()` returns the next line, or `none` at end of input.

<!-- manuscript-example: {"mode":"run","stdin":"line one\n\nlast line","stdout":"line one\n\nlast line\n","cases":[{"stdout":""}]} -->
```manuscript
import stdin, stdout from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn run() Unit!:
    var input = lines(stdin())
    while true:
        let line = try input.read().wait()
        if let text = line:
            try stdout().write("{text}\n")
        else:
            break
    return stdout().flush().wait()

export fn main() Int:
    let outcome = run()
    if let _completed = outcome:
        return 0
    print(outcome.err().message)
    return 1
```

```sh
printf 'line one\n\nlast line' | ms run lines.ms
```

```text
line one

last line
```

An empty line is `""`, and the loop ends at end of input. Line endings (`\n` or `\r\n`) are stripped, and a read failure is returned by `wait()`.

## Parse an integer

Save as `number.ms`. `parse_int()` returns an `Int?`.

<!-- manuscript-example: {"mode":"run","args":["42"],"stdout":"42\n","cases":[{"args":["oops"],"exit_code":1,"stdout":"Enter a whole number\n"}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

fn show(text: String) Unit!:
    if let number = text.parse_int():
        try stdout().write("{number}\n")
        return stdout().flush().wait()
    return error(Error("Enter a whole number"))

export fn main() Int:
    let outcome = show(arguments().get(0, default: "42"))
    if let _written = outcome:
        return 0
    print(outcome.err().message)
    return 1
```

```sh
ms run number.ms -- 42
```

```text
42
```

Use `get(default)` for a default, or `if let` with a failure path ([Optional values](../core-language/types/optionals.md)).

## Parse JSON

Save as `json.ms`. `parse[String]` errors on malformed JSON or another type.

<!-- manuscript-example: {"mode":"run","args":["\"hello\""],"stdout":"hello\n","cases":[{"args":["{"],"exit_code":1,"stdout":"JSON: invalid data: line 1, column 2: unexpected end of input\n"},{"args":["42"],"exit_code":1,"stdout":"JSON: invalid data: at $: expected string, found number\n"}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import parse from "@std/data/json.ms"
import stdout from "@std/io/io.ms"

fn run() Unit!:
    let text = try parse[String](arguments().get(0, default: "\"hello\""))
    try stdout().write("{text}\n")
    return stdout().flush().wait()

export fn main() Int:
    let outcome = run()
    if let _completed = outcome:
        return 0
    print(outcome.err().message)
    return 1
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

Save as `config.ms`. Parse a record directly and serialize it back. Use strict encoding so a value with no JSON representation fails instead of being silently omitted.

<!-- manuscript-example: {"mode":"run","args":["{\"name\":\"Sam\"}"],"stdout":"{\"name\":\"Sam\",\"enabled\":true}\n","cases":[{"args":["{\"name\":\"Ada\",\"enabled\":false,\"extra\":1}"],"stdout":"{\"name\":\"Ada\",\"enabled\":false}\n"},{"args":["{}"],"exit_code":1,"stdout":"JSON: invalid data: at $: missing field \"name\"\n"},{"args":["{\"name\":42}"],"exit_code":1,"stdout":"JSON: invalid data: at $.name: expected string, found number\n"}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import parse, stringify from "@std/data/json.ms"
import stdout from "@std/io/io.ms"

type Config:
    name: String
    enabled: Bool = true

fn run() Unit!:
    let text = arguments().get(0, default: "\{\"name\":\"Sam\"\}")
    let config = try parse[Config](text)
    let encoded = try stringify(config, strict: true)
    try stdout().write("{encoded}\n")
    return stdout().flush().wait()

export fn main() Int:
    let outcome = run()
    if let _completed = outcome:
        return 0
    print(outcome.err().message)
    return 1
```

```sh
ms run config.ms -- '{"name":"Sam"}'
```

```text
{"name":"Sam","enabled":true}
```

- A missing `enabled` takes its default; a missing `name` or wrong type is an error.
- Unknown members are ignored unless `ignore_unknown_fields: false`.
- Write `parse[Config]` explicitly after `try`.
- `stringify` writes fields in declaration order. `strict: true` is opt-in; ordinary `stringify` can omit values without a JSON form. Strict mode still omits `none` record fields.

## Make an HTTP GET request

Save as `get.ms`. `fetch` buffers the body, `check_status()` rejects statuses outside 200–299, and `text()` decodes UTF-8.

<!-- manuscript-example: {"mode":"run","args":["$HTTP_URL"],"http":{"status":200,"body":"hello from a file\n"},"stdout":"hello from a file\n","cases":[{"args":["$HTTP_URL"],"http":{"status":404,"body":"missing"},"exit_code":1,"stdout":"fetch: unexpected status 404\n"},{"args":["invalid URL"],"exit_code":1,"stdout":"HTTP: invalid input\n"},{"exit_code":1,"stdout":"missing URL\n"}]} -->
```manuscript
import arguments from "@std/os/process.ms"
import fetch, FetchOptions from "@std/net/fetch.ms"
import stdout from "@std/io/io.ms"

fn run() Unit!:
    let url = try arguments().first().ok_or(Error("missing URL", kind: "EINVAL"))
    let response = try fetch(url, FetchOptions(max_response_bytes: 1048576)).wait()
    try response.check_status()
    let text = try response.text()
    try stdout().write(text)
    return stdout().flush().wait()

export fn main() Int:
    let outcome = run()
    if let _completed = outcome:
        return 0
    print(outcome.err().message)
    return 1
```

```sh
# In another terminal, serve notes.txt from the current directory:
python3 -m http.server 8000 --bind 127.0.0.1

# In your program's terminal:
ms run get.ms -- http://127.0.0.1:8000/notes.txt
```

The program prints the contents served from `notes.txt`:

```text
hello from a file
```

The server needs Python 3 and a `notes.txt` (from the file-reading recipe). Transport failures, non-success statuses and invalid UTF-8 exit 1; the body is capped at one mebibyte (1,048,576 bytes). Other `FetchOptions` fields keep their defaults, including the 30-second deadline.

For a JSON response, `try response.json[Config]()` decodes into a type such as the `Config` above. Call `check_status()` first when an error status should fail the operation: `fetch` itself returns error statuses as ordinary responses. For repeated requests, bind a pooled `Fetcher` with `let client = try fetcher()`; see the [fetch API](../standard-library/reference/net/fetch.ms.md).

Next: [testing](testing.md) and [counting loops](../core-language/control-flow/loops.md#counting-loops).
