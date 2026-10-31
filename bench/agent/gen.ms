# Regenerates a challenge's examples/cases.json and hidden/cases.json deterministically.
# Usage (from the repository root): ms run bench/agent/gen.ms -- <c03|c05|...|all>
# Large challenges (c51 to c60) need `go` on PATH: their expected outputs come from the Go oracle in oracle/*.ref.
import stderr from "@std/io.ms"
import arguments from "@std/process.ms"
import gen_c03 from "./challenges/c03-csv-group-sum/gen.ms"
import gen_c05 from "./challenges/c05-calculator/gen.ms"
import gen_c09 from "./challenges/c09-ciphers/gen.ms"
import gen_c13 from "./challenges/c13-inventory-orders/gen.ms"
import gen_c14 from "./challenges/c14-dp-suite/gen.ms"
import gen_c16 from "./challenges/c16-maze-bfs/gen.ms"
import gen_c18 from "./challenges/c18-cron-next-runs/gen.ms"
import gen_c25 from "./challenges/c25-log-analyzer/gen.ms"
import gen_c36 from "./challenges/c36-bank-ledger/gen.ms"
import gen_c44 from "./challenges/c44-unified-diff/gen.ms"
import gen_c51 from "./challenges/c51-lisp-interpreter/gen.ms"
import gen_c52 from "./challenges/c52-sql-engine/gen.ms"

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
    if which == "c09" or which == "all":
        gen_c09()
        ran += 1
    if which == "c13" or which == "all":
        gen_c13()
        ran += 1
    if which == "c14" or which == "all":
        gen_c14()
        ran += 1
    if which == "c16" or which == "all":
        gen_c16()
        ran += 1
    if which == "c18" or which == "all":
        gen_c18()
        ran += 1
    if which == "c25" or which == "all":
        gen_c25()
        ran += 1
    if which == "c36" or which == "all":
        gen_c36()
        ran += 1
    if which == "c44" or which == "all":
        gen_c44()
        ran += 1
    if which == "c51" or which == "all":
        gen_c51()
        ran += 1
    if which == "c52" or which == "all":
        gen_c52()
        ran += 1
    if ran == 0:
        stderr().write("unknown challenge {which}\n").get()
        return 2

    return 0
