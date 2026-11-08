// Resource ownership matrix (`make resource-matrix`): generates one program for each combination of a
// standard operation that takes, returns or discards a one-owner resource, a call form (direct call, or a
// method value called later) and an argument form (a temporary, or a named variable), then checks each one.
// A combination the checker rejects is fine: the rule is that anything `ms check` accepts must lower, run and
// close every resource it made exactly once. The oracle needs no expected output per case: `mk` prints
// `made-N`, `close` prints `closed-N`, and the two must match at exit, in Debug and Release.
// A new standard operation that stores, returns or discards a `T` belongs in OPERATIONS below.
// MS names the ms that runs the programs (default target/release/ms).
// Usage: ms run tools/resource-matrix.ms [-- name-filter]
import tool_ms from "./lib.ms"
import temporary, write_file from "@std/os/fs.ms"
import run from "@std/os/process.ms"
import arguments, working_directory from "@std/os/env.ms"
import stdout from "@std/io/io.ms"

let HEADER = """
import Closeable, print from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!:
        print("closed-\{self.id\}")
        return ok(unit)

fn saw(m: Marker) Unit:
    print("saw-\{m.id\}")

fn saw_opt(m: Marker?) Unit:
    print("saw-\{m.is_some()\}")

fn mk(id: Int) Marker:
    print("made-\{id\}")
    return Marker(id)

fn run() Unit:
"""
let FOOTER = """
export fn main() Int:
    run()
    return 0
"""

// One standard operation: the receiver it runs on, its method, its arguments (`@V@` is the resource
// argument) and what to do with a result.
type Operation:
    name: String
    setup: String
    receiver: String
    method: String
    arguments: String
    binds: String
    uses: String

fn op(
    name: String,
    setup: String,
    receiver: String,
    method: String,
    arguments: String,
    binds: String,
    uses: String
) Operation:
    return Operation(name, setup, receiver, method, arguments, binds, uses)

fn list_setup() String: return "var items = [mk(1)]"

fn optional_setup(present: Bool) String:
    if present: return "let held: Marker? = mk(1)"

    return "let held: Marker? = none"

fn result_setup(good: Bool) String:
    if good: return "let held: Marker!Error = ok(mk(1))"

    return "let held: Marker!Error = error(Error(\"x\"))"

fn operations() List[Operation]:
    return [
        op("list_append", list_setup(), "items", "append", "@V@", "", ""),
        op("list_prepend", list_setup(), "items", "prepend", "@V@", "", ""),
        op("list_insert", list_setup(), "items", "insert", "0, @V@", "", ""),
        op("list_set", list_setup(), "items", "set", "0, @V@", "", ""),
        op(
            "list_replace", list_setup(), "items", "replace", "0, @V@", "let r = ",
            "saw(r)"
        ),
        op(
            "list_pop", list_setup(), "items", "pop", "", "let r = ", "saw_opt(r)"
        ),
        op("list_remove", list_setup(), "items", "remove", "0", "", ""),
        op(
            "optional_get_present", optional_setup(true), "held", "get", "@V@",
            "let r = ", "saw(r)"
        ),
        op(
            "optional_get_absent", optional_setup(false), "held", "get", "@V@",
            "let r = ", "saw(r)"
        ),
        op(
            "result_get_ok", result_setup(true), "held", "get", "@V@", "let r = ",
            "saw(r)"
        ),
        op(
            "result_get_error", result_setup(false), "held", "get", "@V@", "let r = ",
            "saw(r)"
        ),
        op(
            "result_to_optional", result_setup(true), "held", "to_optional", "",
            "let r = ", "saw_opt(r)"
        )
    ]

// The program for `o`, called as `call_form` (`direct` or `bound`), with its resource argument made as `arg_form`.
fn program(o: Operation, call_form: String, arg_form: String) String:
    var lines = [o.setup.clone()]
    var argument = ""

    if o.arguments.contains("@V@"):
        var value = "mk(2)"

        if arg_form == "named":
            lines.append("let v = mk(2)")
            value = "v"

        argument = o.arguments.replace("@V@", value)
    else:
        argument = o.arguments.clone()

    if call_form == "bound":
        lines.append("let f = {o.receiver}.{o.method}")
        lines.append("{o.binds}f({argument})")
    else:
        lines.append("{o.binds}{o.receiver}.{o.method}({argument})")

    if o.uses != "": lines.append(o.uses.clone())

    var body = ""
    for line in lines: body = "{body}    {line}\n"
    return "{HEADER}\n{body}\n{FOOTER}\n"

// How many times `prefix` + `id` appears as a line, for each id made.
fn count(lines: List[String], prefix: String) Map[String, Int]:
    var counts = Map[String, Int]()

    for line in lines:
        if not line.starts_with(prefix): continue

        let key = line.trim()
        counts.add(key.clone(), counts.get(key.clone()).get(0) + 1)

    return counts

export fn main() Int:
    let root = working_directory().get()
    let ms = tool_ms(root)
    let scratch = temporary("ms-matrix-").get()
    var filter = ""
    for a in arguments(): filter = a.clone()

    var checked = 0
    var rejected = 0
    var failures = 0

    for o in operations():
        for call_form in ["direct", "bound"]:
            for arg_form in ["temporary", "named"]:
                let name = "{o.name}_{call_form}_{arg_form}"
                if filter != "" and not name.contains(filter): continue

                let file = "{scratch.path()}/{name}.ms"
                write_file(file, program(o, call_form, arg_form)).wait().get()

                let verdict = run(ms.clone(), ["check", file.clone()]).wait()

                if verdict.is_error() or verdict.get().exit_code != 0:
                    rejected += 1

                    let why = verdict.get().stderr.decode_utf8().get("")

                    // Only a checker rule may reject a combination; a program that does not parse is this tool's bug.
                    if why.contains(": parse:"):
                        failures += 1
                        (
                            stdout()
                            .write(
                                "generated: {name} does not parse: {why}\n"
                            )
                            .get()
                        )
                    else if filter != "":
                        stdout().write("rejected {name}: {why}\n").get()

                    continue

                for build in ["debug", "release"]:
                    checked += 1

                    let ran = run(
                        ms.clone(),
                        [
                            "run", file.clone(), "--build-type", build.clone()
                        ]
                    ).wait()

                    if ran.is_error():
                        failures += 1
                        (
                            stdout()
                            .write(
                                "run: {name} ({build}) could not run {ms}\n"
                            )
                            .get()
                        )
                        continue

                    let child = ran.get()
                    let lines = child.stdout.decode_utf8().get("").split("\n")

                    if child.exit_code != 0:
                        failures += 1

                        let why = child.stderr.decode_utf8().get("")
                        (
                            stdout()
                            .write(
                                "exit: {name} ({build}) passed `ms check` but failed: {why}\n"
                            )
                            .get()
                        )
                        continue

                    var made = List[String]()
                    var closed = List[String]()

                    for line in lines:
                        if line.starts_with("made-"): made.append(
                            line.slice(
                                5, line.length()
                            ).get("")
                        )
                        if line.starts_with("closed-"):
                            closed.append(line.slice(7, line.length()).get(""))

                    let made_counts = count(lines, "made-")
                    var wrong = made.length() != closed.length()

                    for id in made:
                        let want = made_counts.get("made-{id}").get(0)
                        var have = 0
                        for c in closed:
                            if c == id: have += 1
                        if want != have: wrong = true

                    if wrong:
                        failures += 1
                        (
                            stdout()
                            .write(
                                "ownership: {name} ({build}) made {made.join(",")} and closed {closed.join(",")}; each resource must close once ({file})\n"
                            )
                            .get()
                        )

    (
        stdout()
        .write(
            "matrix: {checked} runs, {rejected} combinations rejected by the checker, {failures} failing\n"
        )
        .get()
    )

    if checked == 0:
        stdout().write("no combination ran\n").get()
        return 1

    if failures > 0: return 1

    return 0
