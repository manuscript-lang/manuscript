# Verifier used inside Harbor tasks: build /app, run hidden cases, write the reward.
#
# Usage: ms run /tests/grade.ms -- <cases.json> <build-cmd> <run-cmd> <timeout-s> [source-suffix]
# Writes /logs/verifier/reward.txt (1 if every case passes, else 0) and detail.json. export_harbor.ms copies this file
# and the modules it imports next to each other under /tests, keeping their relative layout.
import create_directory, write_file from "@std/os/fs.ms"
import parse, stringify from "@std/data/json.ms"
import arguments from "@std/os/process.ms"
import Case from "./core/model.ms"
import count_workspace from "./core/codetokens.ms"
import bash, env, must_read, nonblank_lines, norm, read_text from "./lib/text.ms"

type LogRow:
    phase: String
    ok: Bool

type Detail:
    built: Bool
    passed: Int
    total: Int
    failed: List[String]
    code_tokens: Int?
    builds: Int
    first_build_ok: Bool
    checks: Int
    error: String?

export fn main() Int:
    let args = arguments()
    let cases = parse[List[Case]](must_read(args[0])).get([])
    let build = args[1].clone()
    let run = args[2].clone()
    let timeout = args[3].parse_int().get(5)
    let suffix = if args.length() > 4: args[4].clone() else: ""
    let app = env("MSBENCH_APP", "/app")
    let out_dir = env("MSBENCH_VERIFIER", "/logs/verifier")
    create_directory(out_dir, recursive: true).get()

    var rows = List[LogRow]()
    for line in nonblank_lines(read_text("{app}/.bench/log.jsonl")):
        rows.append(parse[LogRow](line).get(LogRow("", false)))

    let builds = rows.filter(fn r: r.phase == "build")
    var tokens: Int? = none
    if suffix != "": tokens = count_workspace(app, suffix)

    var first_ok = false
    if let first = builds.first(): first_ok = first.ok

    var detail = Detail(
        false, 0, cases.length(), [], tokens, builds.length(), first_ok,
        rows.count(fn r: (r.phase == "check")), none
    )
    let built = bash(build, app, 600, "")

    if built.code == 0:
        detail.built = true

        for c in cases:
            let ran = bash(run, app, timeout, c.stdin)

            if ran.code == 0 and norm(ran.out) == norm(c.stdout):
                detail.passed += 1
            else:
                detail.failed.append(c.name.clone())
    else:
        detail.error = built.err.slice(
            if built.err.length() > 500: built.err.length() - 500 else: 0,
            built.err.length()
        ).get("")

    write_file("{out_dir}/detail.json", stringify(detail).get(""), replace: true).get()

    let reward = if detail.built and detail.passed == detail.total: "1" else: "0"
    write_file("{out_dir}/reward.txt", reward, replace: true).get()
    return 0
