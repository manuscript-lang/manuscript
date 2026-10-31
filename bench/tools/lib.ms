# Shared helpers for the benchmark drivers under bench/. Run a driver from the repository root with
# `ms run bench/tools/<name>.ms [-- arguments]`.
import Stdio, commands, control, os_type, system from "@std/process.ms"
import read_file, write_file, create_directory, is_absolute, join, remove, access from "@std/fs.ms"
import stderr, stdin, stdout, read_all from "@std/io.ms"
import JsonValue, parse, stringify from "@std/json.ms"
import hex_encode from "@std/encoding.ms"
import sha256 from "@std/crypto.ms"

# Prints `message` and a newline to standard error.
export fn note(message: String) Unit:
    stderr().write("{message}\n").get()

# Reports `message` on standard error and returns the status a driver passes back from `main`.
export fn fail(message: String) Int:
    note(message)
    return 1

# `linux`, `macos` or `windows`.
export fn host() String:
    let os = os_type()
    if os == "Darwin": return "macos"
    if os == "Windows_NT": return "windows"

    return "linux"

# The value of environment variable `name`, or `fallback`.
export fn env(name: String, fallback: String) String:
    let all = control().environment().get(Map[String, String]())
    if let value = all.get(name): return value.clone()

    return fallback

# Nanoseconds since an arbitrary fixed origin on the monotonic clock.
export fn now_ns() Int:
    return control().monotonic_time()

# Output of a finished program; `ok` is false when it could not start.
export type Ran:
    ok: Bool
    code: Int
    stdout: String
    stderr: String

# Runs `program` without a shell and captures both streams as text.
export fn capture(program: String, arguments: List[String], input: String = "") Ran:
    if let out = commands().run(program, arguments, input: input.to_bytes()):
        return Ran(
            true, out.exit_code, out.stdout.decode_utf8().get(""),
            out.stderr.decode_utf8().get("")
        )

    return Ran(false, 125, "", "cannot start {program}\n")

# Runs `program` and returns its stdout, or fails the driver by returning an empty string when it does not exit zero.
export fn output_of(program: String, arguments: List[String]) String:
    let ran = capture(program, arguments)
    if ran.ok and ran.code == 0: return ran.stdout.clone()

    return ""

# Median of a nonempty list of numbers; the mean of the middle pair for an even count.
export fn median(values: List[Float]) Float:
    let sorted = values.sorted()
    let n = sorted.length()
    if n % 2 == 1: return sorted[n / 2]

    return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0

# Median absolute deviation.
export fn mad(values: List[Float]) Float:
    let m = median(values)
    return median(values.map(fn v: if v > m: v - m else: m - v))

export fn minimum(values: List[Float]) Float:
    return values.fold(values[0], fn(a: Float, v: Float) Float: if v < a: v else: a)

export fn maximum(values: List[Float]) Float:
    return values.fold(values[0], fn(a: Float, v: Float) Float: if v > a: v else: a)

# Rotates `items` left by `by` positions.
export fn rotate[T: Clonable](items: List[T], by: Int) List[T]:
    let n = items.length()
    var out = List[T](reserve: n)
    for i in 0..n:
        out.append(items[(i + by) % n].clone())
    return out

# The SHA-256 of the file at `path` as lowercase hex.
export fn file_sha256(path: String) String:
    return hex_encode(sha256(read_file(path).get()))

# Reads a UTF-8 text file.
export fn read_text(path: String) String:
    return read_file(path).get().decode_utf8().get("")

# A validation failure in a driver or table: the evidence is not what the benchmark protocol requires.
export type Invalid:
    text: String

impl Error for Invalid:
    fn message() String:
        return self.text.clone()

# Fails with `text`.
export fn invalid[T](text: String) Result[T, Invalid]:
    return error(Invalid(text))

# `text` unless it is longer than `width`; padded on the left to `width` columns.
export fn right(text: String, width: Int) String:
    return text.pad_start(width, " ")

export fn left(text: String, width: Int) String:
    return text.pad_end(width, " ")

# `value` with a comma between each group of three digits.
export fn grouped(value: Int) String:
    let digits = "{if value < 0: -value else: value}"
    var out = ""
    let n = digits.length()

    for i in 0..n:
        if i > 0 and (n - i) % 3 == 0: out += ","
        out += digits.slice(i, i + 1).get("")

    return if value < 0: "-" + out else: out

# `value` to `digits` decimal places, with grouped thousands.
export fn fixed(value: Float, digits: Int) String:
    let text = value.to_fixed(digits)
    let parts = text.split(".")
    let whole = parts[0].parse_int().get(0)

    let head = if text.starts_with("-") and whole == 0: "-0" else: grouped(whole)

    if parts.length() == 1: return head

    return "{head}.{parts[1]}"

# Parses a positive repeat count.
export fn repeats(text: String) Result[Int, Invalid]:
    if let n = text.parse_int():
        if n > 0: return ok(n)
    return invalid("repeats must be a positive integer")

# The absolute form of `path`, relative to the working directory.
export fn absolute(path: String) String:
    if is_absolute(path): return path.clone()

    return join([control().working_directory().get("."), path])

# Runs `program` in directory `dir`, restoring the working directory afterwards; the working directory is process-wide.
export fn run_in(dir: String, program: String, arguments: List[String]) Ran:
    let here = control().working_directory().get(".")
    control().change_directory(dir).get()

    let ran = capture(program, arguments)
    control().change_directory(here).get()
    return ran

# Fails with the program's stderr unless `ran` exited zero.
export fn must(what: String, ran: Ran) Result[String, Invalid]:
    if ran.ok and ran.code == 0: return ok(ran.stdout.clone())

    return invalid("{what} failed ({ran.code}): {ran.stderr}")

# The `ms` binary: $MS, else target/release/ms, as an absolute path.
export fn ms_binary() String:
    return absolute(env("MS", "target/release/ms"))

# Builds the Manuscript project in `dir` to `out` (a file name inside `dir`'s parent is fine; pass an absolute path).
export fn build_ms(dir: String, out: String) Result[Unit, Invalid]:
    let _stale = remove("{dir}/ms.lock")
    let ran = run_in(dir, ms_binary(), ["build", "ms.toml", "-o", out])
    let _ = try must("ms build {dir}", ran)
    return ok(unit)

# Builds the Go module in `dir` as a static binary.
export fn build_go(dir: String, out: String) Result[Unit, Invalid]:
    control().set_environment("CGO_ENABLED", "0").get()

    let go = env("GO", "go")
    let ran = run_in(
        dir,
        go,
        [
            "build", "-buildvcs=false", "-trimpath", "-ldflags=-s -w -buildid=", "-o",
            out, "."
        ]
    )
    let _ = try must("go build {dir}", ran)
    return ok(unit)

# Compiles one Rust source at the usual release settings plus `flags`.
export fn build_rust(
    source: String,
    out: String,
    flags: List[String]
) Result[Unit, Invalid]:
    var args = ["--edition", "2021", "-C", "opt-level=3", "-C", "codegen-units=1"]
    args = args.concat(flags)
    args = args.concat(["-o", out.clone(), source.clone()])

    let _ = try must("rustc {source}", capture(env("RUSTC", "rustc"), args))
    return ok(unit)

# Runs `exe` with `input` on standard input and returns its standard output.
export fn sample(
    exe: String,
    arguments: List[String],
    input: String = ""
) Result[String, Invalid]:
    return must(exe, capture(exe, arguments, input))

# Prints the text of `result` to standard output and returns 0, or reports its error and returns 1.
export fn finish(result: Result[String, Error]) Int:
    if let text = result:
        stdout().write(text + "\n").get()
        return 0

    return fail(result.err().message())

# Parses `--name value` pairs. A name outside `known` or a missing value is an error; `required` names must be present.
export fn options(
    args: List[String],
    known: List[String],
    required: List[String]
) Result[Map[String, String], Invalid]:
    var found = Map[String, String]()
    var i = 0

    while i < args.length():
        let flag = args[i]
        if (
            not flag.starts_with("--")
            or not known.contains(flag.slice(2, flag.length()).get(""))
        ):
            return invalid("unknown argument: {flag}")
        if i + 1 >= args.length(): return invalid("{flag} needs a value")

        found.add(flag.slice(2, flag.length()).get(""), args[i + 1].clone())
        i += 2

    for name in required:
        if not found.contains(name): return invalid("--{name} is required")
    return ok(found)

# Every ordering of `items`, in lexicographic order of position.
export fn permutations[T: Clonable](items: List[T]) List[List[T]]:
    if items.length() <= 1: return [items.clone()]

    var out = List[List[T]]()

    for i in 0..items.length():
        var rest = List[T]()
        for j in 0..items.length():
            if j != i: rest.append(items[j].clone())

        for tail in permutations(rest):
            var order = [items[i].clone()]
            order = order.concat(tail)
            out.append(order)

    return out

# Creates `path` and its parents; an existing directory is fine.
export fn ensure_directory(path: String) Unit:
    create_directory(path, recursive: true).get()

# Writes `text` to `path`.
export fn write_text(path: String, text: String) Unit:
    write_file(path, text, replace: true).get()

# Whether `path` exists.
export fn exists(path: String) Bool:
    return access(path, 0).is_ok()

# Reports a usage error and returns status 2.
export fn usage(message: String) Int:
    note(message)
    return 2

# `.exe` on Windows, else empty.
export fn exe() String:
    if host() == "windows": return ".exe"

    return ""

# A short platform description such as `linux-amd64`.
export fn platform() String:
    let info = system().info()
    return "{info.os}-{info.architecture}"

# All of standard input as text.
export fn read_stdin() String:
    return read_all(stdin(), none).get().decode_utf8().get("")

# Runs `ms bench` for the bench/perf/stdlib suite and returns its JSON document.
export fn stdlib_bench(ms: String, samples: Int, filter: String) Result[String, Invalid]:
    var args = ["bench", "ms.toml", "--json", "--samples", "{samples}"]
    if filter != "": args = args.concat(["--filter", filter.clone()])
    return must("ms bench", run_in("bench/perf/stdlib", ms, args))

# JSON construction helpers; a record holding a Map is not Data, so reports are built as JsonValue objects.
export fn jstr(text: String) JsonValue:
    return JsonValue.StringValue(text)

export fn jint(n: Int) JsonValue:
    return JsonValue.NumberValue("{n}")

export fn jfloat(x: Float) JsonValue:
    return JsonValue.NumberValue("{x}")

export fn jbool(b: Bool) JsonValue:
    return JsonValue.BoolValue(b)

export fn jobject(members: Map[String, JsonValue]) JsonValue:
    return JsonValue.ObjectValue(members)

export fn jlist(items: List[JsonValue]) JsonValue:
    return JsonValue.ArrayValue(items)

# `value` as indented JSON followed by a newline.
export fn dump(value: JsonValue) String:
    return stringify(value, none, 2).get("") + "\n"

# Runs `program` in `dir` with the parent's streams and returns its exit status (125 when it cannot start).
export fn run_inherit(dir: String, program: String, arguments: List[String]) Int:
    let here = control().working_directory().get(".")
    control().change_directory(dir).get()

    var code = 125

    if let child = commands().spawn(
        program, arguments, stdin: Stdio.Null, stdout: Stdio.Inherit,
        stderr: Stdio.Inherit
    ):
        code = child.wait().get(125)
        if code < 0 or code > 125: code = 125
    else:
        note("cannot start {program}")

    control().change_directory(here).get()
    return code

# Compiles bench/perf/representative/rss.c into `dir`. A parent cannot read the peak resident set of a finished child through
# @std/process (ResourceUsage describes only the calling process), so Unix drivers measure it with this small helper.
export fn build_rss(dir: String) Result[String, Invalid]:
    let out = "{dir}/rss"
    let _ = try must(
        "cc rss.c",
        capture(
            env("CC", "cc"),
            ["-O2", "bench/perf/representative/rss.c", "-o", out.clone()]
        )
    )
    return ok(out)

# Runs `program arguments` under the rss helper and returns the child's peak resident set in KiB. The child's output is captured in `ran`.
export type RssRun:
    kib: Int
    ran: Ran

export fn rss_run(
    rss: String,
    record: String,
    program: String,
    arguments: List[String],
    input: String = ""
) Result[RssRun, Invalid]:
    let ran = capture(rss, [record.clone(), program.clone()].concat(arguments), input)
    if not ran.ok or ran.code != 0: return invalid(
        "{program} failed ({ran.code}): {ran.stderr}"
    )

    let doc = parse[JsonValue](read_text(record))
    if doc.is_error(): return invalid("rss helper wrote no record")

    let kib = doc.get(JsonValue.Null).get_in(["maxrss_kib"]).get(
        JsonValue.Null
    ).as_int().get(-1)
    if kib < 0: return invalid("rss helper wrote no record")

    return ok(RssRun(kib, ran))
