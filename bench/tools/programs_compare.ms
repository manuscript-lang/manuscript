# Compares two already-built revisions against shared handwritten Go samples.
# Usage: ms run bench/tools/programs_compare.ms -- --before B --after A --go G --input I --output DIR [--repeats 30]
import absolute, ensure_directory, fail, finish, options, permutations, read_text, sample, write_text from "./lib.ms"
import summarize from "./programs_table.ms"
import arguments from "@std/os/process.ms"

fn lines_of(version: String, content: String) List[String]:
    return content.split("\n").filter(fn l: l != "").map(fn l: "{version} {l}")

fn run(opts: Map[String, String], n: Int) Result[String, Error]:
    let names = ["go", "before", "after"]
    var programs = Map[String, String]()
    for name in names:
        programs.add(name.clone(), absolute(opts.get(name).get("")))

    let orders = permutations(names)
    let input = read_text(opts.get("input").get(""))
    var raw = Map[String, List[String]]()
    raw.add("before", List[String]())
    raw.add("after", List[String]())

    for i in 0..n:
        var results = Map[String, String]()
        for version in orders[i % orders.length()]:
            results.add(
                version.clone(), try sample(programs.get(version).get(""), [], input)
            )

        for revision in ["before", "after"]:
            var lines = raw.get(revision).get([])
            lines = lines.concat(lines_of("go", results.get("go").get("")))
            lines = lines.concat(lines_of("ms", results.get(revision).get("")))
            raw.add(revision.clone(), lines)

    let out = opts.get("output").get("")
    ensure_directory(out)

    var report = List[String]()

    for revision in ["before", "after"]:
        let lines = raw.get(revision).get([])
        write_text("{out}/programs-{revision}.txt", lines.map(fn l: l + "\n").join(""))

        let table = try summarize(lines, n)
        write_text("{out}/programs-{revision}.md", table + "\n")
        report.append("{revision}\n{table}")

    return ok(report.join("\n"))

export fn main() Int:
    let parsed = options(
        arguments(), ["before", "after", "go", "input", "output", "repeats"],
        ["before", "after", "go", "input", "output"]
    )
    if parsed.is_error(): return fail(parsed.err().message())

    let opts = parsed.get(Map[String, String]())
    let n = opts.get("repeats").get("30").parse_int().get(0)
    if n < 1: return fail("repeats must be positive")

    return finish(run(opts, n))
