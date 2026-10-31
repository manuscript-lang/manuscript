# Small helpers shared by the benchmark tools: environment, files, shell commands.
import read_file, write_file, create_directory, dirname from "@std/fs.ms"
import compile from "@std/string.ms"
import Duration, seconds from "@std/time.ms"
import CommandError, commands, control from "@std/process.ms"

# The value of environment variable `name`, or `fallback`.
export fn env(name: String, fallback: String) String:
    let all = control().environment().get(Map[String, String]())
    if let value = all.get(name): return value.clone()

    return fallback

# The text of the file at `path`; empty when it cannot be read.
export fn read_text(path: String) String:
    if let data = read_file(path).to_optional(): return data.decode_utf8().get("")

    return ""

# The text of the file at `path`; a missing file stops the program.
export fn must_read(path: String) String:
    return read_file(path).get().decode_utf8().get("")

# Replaces the file at `path`, creating its directory first.
export fn write_text(path: String, text: String) Unit:
    create_directory(dirname(path), recursive: true).get()
    write_file(path, text, replace: true).get()

# Trailing whitespace removed from every line and from the whole text, as the graders compare output.
export fn norm(text: String) String:
    if text.trim().is_empty(): return ""

    return text.trim_end().split("\n").map(fn line: line.trim_end()).join("\n")

# The nonblank lines of `text`.
export fn nonblank_lines(text: String) List[String]:
    return text.split("\n").filter(fn l: not l.trim().is_empty())

# What a finished shell command left behind.
export type Ran:
    code: Int
    out: String
    err: String
    seconds: Float

# Runs `command` with `bash -c` in directory `cwd`, feeding it `input`. A command still running after
# `timeout_s` seconds is killed and reports status 124 with "timeout" on standard error.
export fn bash(command: String, cwd: String, timeout_s: Int, input: String) Ran:
    return run_in("bash", ["-c", "cd \"$0\" && {command}", cwd.clone()], timeout_s, input)

# Runs `program` with `arguments` and the same timeout rule as `bash`.
export fn run_in(program: String, arguments: List[String], timeout_s: Int, input: String) Ran:
    let start = control().monotonic_time()
    let result = commands().run(program, arguments, input: input.to_bytes(), timeout: seconds(timeout_s))
    let elapsed = (control().monotonic_time() - start).to_float() / 1000000000.0
    if let done = result.to_optional():
        return Ran(done.exit_code, done.stdout.decode_utf8().get(""), done.stderr.decode_utf8().get(""), elapsed)

    if result.err() == CommandError.Timeout: return Ran(124, "", "timeout", elapsed)

    return Ran(127, "", "cannot start {program}", elapsed)

# `text.split(separator, maxsplit)` as Python defines it: at most `splits` splits, the rest stays in the last piece.
export fn split_max(text: String, separator: String, splits: Int) List[String]:
    var out = List[String]()
    var rest = text.clone()
    while out.length() < splits:
        let at = rest.index_of(separator)
        if at.is_none(): break

        out.append(rest.slice(0, at.get(0)).get(""))
        rest = rest.slice(at.get(0) + separator.length(), rest.length()).get("")
    out.append(rest)
    return out

# `text.strip(" ")`: the spaces at both ends removed.
export fn strip_spaces(text: String) String:
    var start = 0
    var end = text.length()
    while start < end and text.get(start) == " ": start += 1
    while end > start and text.get(end - 1) == " ": end -= 1
    return text.slice(start, end).get("")

# Whether the regular expression `pattern` matches all of `text`, as Python's `re.fullmatch`.
export fn full_match(pattern: String, text: String) Bool:
    if let re = compile("^(?:{pattern})$").to_optional(): return re.matches(text)

    return false

# `text.split()`: the words between runs of whitespace.
export fn words(text: String) List[String]:
    var out = List[String]()
    var current = ""
    for ch in text.chars():
        if ch.trim().is_empty():
            if current != "": out.append(current.clone())
            current = ""
        else:
            current = current + ch
    if current != "": out.append(current.clone())
    return out
