# Regenerates a challenge's examples/cases.json and hidden/cases.json deterministically.
# Usage (from the repository root): ms run bench/agent/gen.ms -- <c03|c05|...|all>
# Large challenges (c51 to c60) need `go` on PATH: their expected outputs come from the Go oracle in oracle/*.ref.
import stderr from "@std/io.ms"
import arguments from "@std/process.ms"
import gen_c03 from "./challenges/c03-csv-group-sum/gen.ms"
import gen_c05 from "./challenges/c05-calculator/gen.ms"

export fn main() Int:
    let args = arguments()
    if args.length() != 1:
        stderr().write("usage: gen.ms <challenge id prefix such as c03 | all>\n").get()
        return 2

    let which = args[0].clone()
    var ran = 0
    if which == "c03" or which == "all":
        gen_c03()
        ran += 1
    if which == "c05" or which == "all":
        gen_c05()
        ran += 1
    if ran == 0:
        stderr().write("unknown challenge {which}\n").get()
        return 2

    return 0
