+++
title = "Files and standard input"
weight = 3
+++

# Files and standard input

Read and write text files and process standard input line by line. Each program is a complete `.ms` file: save it under the shown name and run the command from that directory ([getting started](../learn/getting-started.md)). `main` returns the exit status.

## Read a UTF-8 text file

Save as `read.ms`. `decode_utf8()` returns `null` for invalid UTF-8.

<!-- manuscript-example: {"mode":"run","args":["notes.txt"],"files":{"notes.txt":"hello from a file\n"},"stdout":"hello from a file\n","cases":[{"args":["missing.txt"],"exit_code":1},{"exit_code":1}]} -->
```manuscript
import (
    stdout from "@std/io/io.ms",
    arguments from "@std/os/env.ms",
    read_file from "@std/os/fs.ms",
)

fn run() Result[Void, Error] {
    path := ok_or(arguments().first(), Error("missing path", kind: "EINVAL"))?
    text := (
        read_file(path, max_bytes: 1048576).wait()?
        | .decode_utf8()
        | ok_or(Error("not UTF-8", kind: "EBADMSG"))?
    )
    stdout().write(text)?
    return stdout().flush()
}

fn main() Void! {
    return run()
}
```

```sh
printf 'hello from a file\n' > notes.txt
ms run read.ms -- notes.txt
```

```text
hello from a file
```

`max_bytes` bounds the read; any failure exits nonzero.

## Write a text file

Save as `write.ms`. `replace: false` fails if the file exists.

<!-- manuscript-example: {"mode":"run","args":["saved.txt"],"want_files":{"saved.txt":"saved notes\n"},"cases":[{"args":["saved.txt"],"files":{"saved.txt":"keep me"},"want_files":{"saved.txt":"keep me"},"exit_code":1},{"exit_code":1}]} -->
```manuscript
import (
    arguments from "@std/os/env.ms",
    write_file from "@std/os/fs.ms",
)

fn run() Result[Void, Error] {
    path := ok_or(arguments().first(), Error("missing path", kind: "EINVAL"))?
    return write_file(path, "saved notes\n", replace: false).wait()
}

fn main() Void! {
    return run()
}
```

```sh
ms run write.ms -- saved.txt
cat saved.txt
```

```text
saved notes
```

The program succeeds silently; `cat` shows the saved content. Use `replace: true` to overwrite. Relative paths use the working directory.

## Read standard input line by line

Save as `lines.ms`. `lines` wraps a byte stream as a stream of lines; `next()` returns the next line, or `null` at end of input.

<!-- manuscript-example: {"mode":"run","stdin":"line one\n\nlast line","stdout":"line one\n\nlast line\n","cases":[{"stdout":""}]} -->
```manuscript
import (
    stdin, stdout from "@std/io/io.ms",
    lines from "@std/io/steps.ms",
)

fn run() Result[Void, Error] {
    var input = lines(stdin())

    while true {
        line := input.next()?

        if line == null { break }
        stdout().write(f"{line}\n")?
    }

    return stdout().flush()
}

fn main() Void! {
    return run()
}
```

```sh
printf 'line one\n\nlast line' | ms run lines.ms
```

```text
line one

last line
```

An empty line is `""`, and the loop ends at end of input. Line endings (`\n` or `\r\n`) are stripped, and a read failure is returned by `wait()`.

## Find files by pattern

Save as `find.ms`. `glob` walks a directory and returns the entries that match any include pattern, sorted by path. Each path is relative to the root and `/`-separated on every platform.

`**` crosses directories. A pattern that ends in `/` matches directories only, as in a shell. `exclude` patterns skip an entry and do not enter a skipped directory, and `max_results` bounds a walk of an unknown tree.

<!-- manuscript-example: {"mode":"run","stdout":"src/main.ms\nsrc/util/text.ms\nsrc\nsrc/util\n"} -->
```manuscript
import GlobOptions, create_directory, glob, temporary, write_file from "@std/os/fs.ms"

fn main() Void! {
    dir := temporary("glob-")?
    root := dir.path()
    create_directory(f"{root}/src/util", true)?
    write_file(f"{root}/src/main.ms", "a").wait()?
    write_file(f"{root}/src/util/text.ms", "b").wait()?
    write_file(f"{root}/notes.txt", "c").wait()?
    for entry in glob(root, GlobOptions(patterns: ["**/*.ms"]))? {
        print(entry.path)
    }
    for entry in glob(root, GlobOptions(patterns: ["**/"]))? {
        print(entry.path)
    }
}
```
