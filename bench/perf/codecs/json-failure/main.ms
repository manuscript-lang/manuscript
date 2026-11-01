import parse, JsonError from "@std/data/json.ms"
import StringBuilder from "@std/string.ms"
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"
import monotonic from "@std/os/time.ms"

extern fn codec_bench_cpu_ns() Int

export fn main() Int:
    let args = arguments()
    let size = args[0].parse_int().get()
    let rounds = args[1].parse_int().get()
    let shape = args[2]
    let valid = shape.ends_with("valid")
    let typed = shape.starts_with("typed")
    var expected = StringBuilder()
    var input = StringBuilder()

    if valid: input.append("\"")
    else: input.append("]")

    for i in 0..size:
        expected.append("a")

        if shape.ends_with("escaped"): input.append("\\")
        else: input.append("a")

    if valid: input.append("\"")

    let wanted = expected.build()
    let text = input.build()
    var checksum = 0
    let cpu_start = codec_bench_cpu_ns()
    if cpu_start < 0: return 4

    let start = monotonic()

    for i in 0..rounds:
        if typed:
            let result = parse[String](text)

            if valid:
                if result.is_error(): return 2
                if result.get() != wanted: return 8
            else:
                if result.is_ok(): return 3
                if result.err() != JsonError.InvalidData: return 5
        else:
            let result = parse(text)

            if valid:
                if result.is_error(): return 2

                let parsed = result.get()
                if not parsed.as_string().is_some(): return 7
                if parsed.as_string().get("") != wanted: return 8
            else:
                if result.is_ok(): return 3
                if result.err() != JsonError.InvalidData: return 5

        checksum += 1

    let elapsed = monotonic().difference(start).to_nanoseconds()
    let cpu = codec_bench_cpu_ns() - cpu_start
    if cpu <= 0: return 6

    stdout().write("{size} {rounds} {shape} {checksum} {elapsed} {cpu}\n").get()
    return 0
