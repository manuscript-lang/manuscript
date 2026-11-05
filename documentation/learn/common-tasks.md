+++
title = "Task recipes"
weight = 4
aliases = ["/learn/best-practices/"]
+++

# Task recipes

Review an agent’s inputs, outputs and error paths in complete small programs; these alpha APIs may change.

## Print a line

Save as `hello.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n","filename":"hello.ms"} -->
```manuscript {filename="hello.ms"}
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

- `print` is in the prelude and adds a newline.

## Read command-line arguments

Save as `args.ms`.

<!-- manuscript-example: {"mode":"run","args":["Sam","Ada"],"stdout":"Hello, Sam!\nHello, Ada!\n","cases":[{"stdout":""}],"filename":"args.ms"} -->
```manuscript {filename="args.ms"}
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

fn run() Unit!:
    for name in arguments():
        try stdout().write("Hello, {name}!\n")
    try stdout().flush().wait()
    return ok(unit)

export fn main() Int:
    if let _done = run():
        return 0
    return 1
```

```sh
ms run args.ms -- Sam Ada
```

```text
Hello, Sam!
Hello, Ada!
```

- Arguments after `--` exclude the executable name.
- Explicit flushing lets output failures reach `run`’s error result.

## Parse subcommands and flags

Save as `tool.ms`.

<!-- manuscript-example: {"mode":"run","args":["hello","Ada","-n","2"],"stdout":"Hello, Ada!\nHello, Ada!\n","filename":"tool.ms"} -->
```manuscript {filename="tool.ms"}
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

- The typed handler receives parsed flags and positional arguments.
- Usage errors exit with status 2.

## Read a UTF-8 text file

Save as `read.ms`; shell commands below use a POSIX terminal.

<!-- manuscript-example: {"mode":"run","args":["notes.txt"],"files":{"notes.txt":"hello from a file\n"},"stdout":"hello from a file\n","cases":[{"args":["missing.txt"],"exit_code":1},{"exit_code":1}],"filename":"read.ms"} -->
```manuscript {filename="read.ms"}
import arguments from "@std/os/process.ms"
import read_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"

fn run() Unit!:
    let path = try arguments().first().ok_or(Error("missing path", kind: "EINVAL"))
    let text = try read_file(path, max_bytes: 1048576).wait()
        | .decode_utf8().ok_or(Error("not UTF-8", kind: "EBADMSG"))
        | try
    try stdout().write(text)
    try stdout().flush().wait()
    return ok(unit)

export fn main() Int:
    if let _done = run():
        return 0
    return 1
```

```sh
printf 'hello from a file\n' > notes.txt
ms run read.ms -- notes.txt
```

```text
hello from a file
```

- Reads are capped at one mebibyte; invalid UTF-8 or a missing path exits 1.

## Write a text file

Save as `write.ms`; shell commands below use a POSIX terminal.

<!-- manuscript-example: {"mode":"run","args":["saved.txt"],"want_files":{"saved.txt":"saved notes\n"},"cases":[{"args":["saved.txt"],"files":{"saved.txt":"keep me"},"want_files":{"saved.txt":"keep me"},"exit_code":1},{"exit_code":1}],"filename":"write.ms"} -->
```manuscript {filename="write.ms"}
import arguments from "@std/os/process.ms"
import write_file from "@std/os/fs.ms"

fn run() Unit!:
    let path = try arguments().first().ok_or(Error("missing path", kind: "EINVAL"))
    try write_file(path, "saved notes\n", replace: false).wait()
    return ok(unit)

export fn main() Int:
    if let _done = run():
        return 0
    return 1
```

```sh
ms run write.ms -- saved.txt
cat saved.txt
```

```text
saved notes
```

- Run in a directory without `saved.txt`; `replace: false` preserves existing files.
- The program is silent; `cat` shows the saved content.

## Read standard input line by line

Save as `lines.ms`; shell commands below use a POSIX terminal.

<!-- manuscript-example: {"mode":"run","stdin":"line one\n\nlast line","stdout":"line one\n\nlast line\n","cases":[{"stdout":""}],"filename":"lines.ms"} -->
```manuscript {filename="lines.ms"}
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
    try stdout().flush().wait()
    return ok(unit)

export fn main() Int:
    if let _done = run():
        return 0
    return 1
```

```sh
printf 'line one\n\nlast line' | ms run lines.ms
```

```text
line one

last line
```

- An empty line is text; end of input ends the loop.

## Parse an integer

Save as `number.ms`.

<!-- manuscript-example: {"mode":"run","args":["42"],"stdout":"42\n","cases":[{"args":["oops"],"exit_code":1}],"filename":"number.ms"} -->
```manuscript {filename="number.ms"}
import arguments from "@std/os/process.ms"

fn run() Unit!:
    let input = arguments().get(0, default: "42")
    let number = try input.parse_int().ok_or(Error("expected an integer"))
    print(number)
    return ok(unit)

export fn main() Int:
    if let _done = run():
        return 0
    return 1
```

```sh
ms run number.ms -- 42
```

```text
42
```

- `parse_int()` returns `Int?`; `ok_or` turns absence into an expected error.

## Parse JSON

Save as `json.ms`; shell commands below use a POSIX terminal.

<!-- manuscript-example: {"mode":"run","args":["\"hello\""],"stdout":"hello\n","cases":[{"args":["{"],"exit_code":1},{"args":["42"],"exit_code":1}],"filename":"json.ms"} -->
```manuscript {filename="json.ms"}
import arguments from "@std/os/process.ms"
import parse from "@std/data/json.ms"
import stdout from "@std/io/io.ms"

fn run() Unit!:
    let text = try parse[String](arguments().get(0, default: "\"hello\""))
    try stdout().write("{text}\n")
    try stdout().flush().wait()
    return ok(unit)

export fn main() Int:
    if let _done = run():
        return 0
    return 1
```

```sh
ms run json.ms -- '"hello"'
```

```text
hello
```

- Malformed JSON or a different shape exits 1.

## Read and write typed JSON

<span id="let-types-describe-your-data"></span>

Save as `config.ms`; shell commands below use a POSIX terminal.

<!-- manuscript-example: {"mode":"run","args":["{\"name\":\"Sam\"}"],"stdout":"{\"name\":\"Sam\",\"enabled\":true}\n","cases":[{"args":["{\"name\":\"Ada\",\"enabled\":false,\"extra\":1}"],"stdout":"{\"name\":\"Ada\",\"enabled\":false}\n"},{"args":["{}"],"exit_code":1},{"args":["{\"name\":42}"],"exit_code":1}],"filename":"config.ms"} -->
```manuscript {filename="config.ms"}
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
    try stdout().flush().wait()
    return ok(unit)

export fn main() Int:
    if let _done = run():
        return 0
    return 1
```

```sh
ms run config.ms -- '{"name":"Sam"}'
```

```text
{"name":"Sam","enabled":true}
```

- Missing fields use declared defaults; unknown fields are ignored by default.
- `strict: true` rejects values without a JSON form; absent record fields remain omitted.

## Make an HTTP GET request

Save as `http_test.ms`; this test starts a local server and reads its response.

<!-- manuscript-example: {"mode":"test","filename":"http_test.ms","stdout":"RUN http_test.ms::read an HTTP response\nPASS http_test.ms::read an HTTP response\n1 tests, 0 failed\n"} -->
```manuscript {filename="http_test.ms"}
import serve from "@std/net/net.ms"
import buffered, text from "@std/net/http.ms"
import fetch from "@std/net/fetch.ms"
import expect_equal from "@std/test/test.ms"

test "read an HTTP response":
    let handler = buffered(fn request: text(200, "Hello!"))
    let server = try serve("127.0.0.1:0", handler)
    let response = try fetch("http://{server.address()}/").wait()
    try response.check_status()
    try expect_equal(try response.text(), "Hello!")
```

```sh
ms test http_test.ms
```

```text
RUN http_test.ms::read an HTTP response
PASS http_test.ms::read an HTTP response
1 tests, 0 failed
```

- `fetch` buffers the body; `check_status` rejects non-success statuses and `text` validates UTF-8.
- Scope-end drop stops the server; use [fetch options](../standard-library/reference/net/fetch.ms.md) to bound response size and deadlines.

Next: [testing](testing.md), [resource cleanup](../core-language/cleanup/_index.md), [API reference](../standard-library/reference/_index.md).
