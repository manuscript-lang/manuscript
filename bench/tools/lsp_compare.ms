# Interleaves two already-built LSP harnesses and rejects mismatched output or work (replaces bench/perf/lsp*/compare.py).
# Usage: ms run bench/tools/lsp_compare.ms -- <hover|outline|semantic> BEFORE AFTER --out FILE.csv [--samples 9] [--cpu N]
# Suites are the case lists of the three studies: `hover` (bench/perf/lsp), `outline` (lsp-outline), `semantic` (lsp-semantic).
# Harness output is `mode,count,rounds,shape,elapsed_ns,checksum,size,rss`. The CSV has a cpu column (empty without --cpu).
import Invalid, absolute, fail, invalid, median, options, sample, write_text from "./lib.ms"
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

type Case:
    mode: String
    count: Int
    shape: String

fn add(cases: List[Case], mode: String, count: Int, shape: String) List[Case]:
    var out = cases.clone()
    out.append(Case(mode.clone(), count, shape.clone()))
    return out

fn hover_cases() List[Case]:
    var cases = List[Case]()
    for mode in ["hover", "hover-first", "hover-blank", "hover-name"]:
        for count in [1, 100, 1000, 4000]:
            cases = add(cases, mode, count, "ascii")
    for shape in ["unicode", "crlf", "long"]:
        cases = add(cases, "hover", 1000, shape)
    for mode in ["index", "symbols", "semantic", "references", "completion", "format"]:
        for count in [1, 100, 1000]:
            cases = add(cases, mode, count, "ascii")

    for count in [1, 100, 1000, 4000]:
        cases = add(cases, "references", count, "references")
        cases = add(cases, "references-first", count, "ascii")

    return add(cases, "references-first", 1, "tail")

fn outline_cases() List[Case]:
    var cases = List[Case]()
    for count in [1, 16, 128, 1000]:
        for size in [0, 1024, 100000]:
            cases = add(cases, "symbols", count, "spaces-{size}")
    for count in [1, 1000]:
        for shape in ["spaces-1000000", "spaces-crlf-100000", "tail"]:
            cases = add(cases, "symbols", count, shape)
    for count in [1, 100, 1000]:
        for shape in ["unicode", "crlf"]:
            cases = add(cases, "symbols", count, shape)
    for mode in [
        "hover", "hover-name", "hover-blank", "index", "symbols", "semantic",
        "references", "completion", "format"
    ]:
        for count in [1, 100, 1000]:
            cases = add(cases, mode, count, "ascii")
    return cases

fn semantic_cases() List[Case]:
    var cases = List[Case]()
    for count in [1, 8, 32, 128, 512, 2048, 8192]:
        for shape in ["list-flat", "list-lines"]:
            cases = add(cases, "semantic", count, shape)
    for count in [1, 128, 2048]:
        for shape in ["list-unicode", "list-crlf", "list-unicode-crlf"]:
            cases = add(cases, "semantic", count, shape)
    for count in [1, 100, 1000]:
        cases = add(cases, "semantic", count, "ascii")
    for count in [1, 1000]:
        for shape in ["unicode", "crlf", "unfinished", "unfinished-crlf"]:
            cases = add(cases, "semantic", count, shape)
    cases = add(cases, "semantic", 1000, "long")
    cases = add(cases, "semantic", 1, "tail")
    for mode in [
        "hover", "hover-name", "hover-blank", "index", "symbols", "references",
        "completion", "format"
    ]:
        for count in [1, 100, 1000]:
            cases = add(cases, mode, count, "ascii")
    for count in [1, 32, 512, 8192]:
        for shape in ["list-flat", "list-lines"]:
            cases = add(cases, "format", count, shape)
    return cases

type Run:
    elapsed: Int
    checksum: Int
    size: Int
    rss: Int

fn run_harness(binary: String, c: Case, rounds: Int, cpu: String) Result[Run, Invalid]:
    var program = binary.clone()
    var args = [c.mode.clone(), "{c.count}", "{rounds}", c.shape.clone()]

    if cpu != "":
        args = ["--cpu-list", cpu.clone(), binary.clone()].concat(args)
        program = "taskset"

    let out = try sample(program, args)
    let fields = out.trim().split(",")
    if fields.length() != 8: return invalid("malformed harness row: {out.trim()}")
    if (
        fields[0] != c.mode
        or fields[1] != "{c.count}"
        or fields[2] != "{rounds}"
        or fields[3] != c.shape
    ):
        return invalid("harness row does not echo its arguments: {out.trim()}")

    var n = List[Int]()

    for i in 4..8:
        let v = fields[i].parse_int()
        if v.is_none(): return invalid("not an integer: {fields[i]}")

        n.append(v.get(0))

    return ok(Run(n[0], n[1], n[2], n[3]))

fn compare(
    suite: String,
    before: String,
    after: String,
    out: String,
    samples: Int,
    cpu: String
) Result[Unit, Error]:
    let cases = if suite == "hover": hover_cases() else: if suite == "outline": outline_cases() else: semantic_cases()

    var paths = Map[String, String]()
    paths.add("before", before.clone())
    paths.add("after", after.clone())

    var rows = [
        "mode,count,shape,sample,binary,rounds,elapsed_ns,checksum_per_query,source_bytes,peak_rss_kib,cpu"
    ]

    for c in cases:
        var rounds = Map[String, Int]()
        var expected = Run(0, -1, -1, 0)
        var seen = false

        for name in ["before", "after"]:
            let first = try run_harness(paths.get(name).get(""), c, 1, cpu)

            if not seen:
                expected = Run(0, first.checksum, first.size, 0)
                seen = true

            if first.checksum != expected.checksum or first.size != expected.size:
                return invalid(
                    "{c.mode} {c.count} {c.shape}: before and after disagree"
                )

            let want = (30000000 + first.elapsed - 1) / first.elapsed
            rounds.add(
                name.clone(),
                if want < 1: 1 else: (
                    if want > 100000: 100000 else: want
                )
            )

        var observed = Map[String, List[Float]]()
        observed.add("before", List[Float]())
        observed.add("after", List[Float]())

        for s in 0..samples:
            for name in (if s % 2 == 0: ["before", "after"] else: ["after", "before"]):
                let r = rounds.get(name).get(1)
                let got = try run_harness(paths.get(name).get(""), c, r, cpu)
                if got.checksum != expected.checksum or got.size != expected.size:
                    return invalid("{c.mode} {c.count} {c.shape}: output changed")

                var list = observed.get(name).get([])
                list.append(got.elapsed.to_float() / r.to_float())
                observed.add(name.clone(), list)
                rows.append(
                    "{c.mode},{c.count},{c.shape},{s},{name},{r},{got.elapsed},{got.checksum},{got.size},{got.rss},{cpu}"
                )

        let old = median(observed.get("before").get([]))
        let new = median(observed.get("after").get([]))
        (
            stdout()
            .write(
                "{c.mode},{c.count},{c.shape},before={old.to_fixed(0)}ns,after={new.to_fixed(0)}ns,ratio={(new / old).to_fixed(3)}\n"
            )
            .get()
        )

    write_text(out, rows.join("\n") + "\n")
    return ok(unit)

export fn main() Int:
    let args = arguments()
    if args.length() < 3 or not ["hover", "outline", "semantic"].contains(args[0]):
        return fail(
            "usage: lsp_compare.ms -- <hover|outline|semantic> BEFORE AFTER --out FILE [--samples N] [--cpu N]"
        )

    let parsed = options(
        args.slice(3, args.length()).get([]), ["out", "samples", "cpu"], ["out"]
    )
    if parsed.is_error(): return fail(parsed.err().message())

    let opts = parsed.get(Map[String, String]())

    let default_samples = if args[0] == "hover": 9 else: 10

    let samples = opts.get("samples").get("{default_samples}").parse_int().get(0)
    if samples < 5: return fail("--samples must be at least 5")

    let result = compare(
        args[0], absolute(args[1].clone()), absolute(args[2].clone()),
        opts.get("out").get(""), samples, opts.get("cpu").get("")
    )
    if result.is_error(): return fail(result.err().message())

    return 0
