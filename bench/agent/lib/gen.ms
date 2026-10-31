# Shared pieces of the challenge generators: the case record, the committed file layout and the Go oracle.
import panic from "@std/core.ms"
import copy_file, create_directory, remove, temporary_directory, write_file from "@std/fs.ms"
import stderr from "@std/io.ms"
import dumps_data from "./pyjson.ms"
import bash, write_text from "./text.ms"
import root from "../core/model.ms"

# One input and the exact output expected for it.
export type GenCase:
    name: String
    stdin: String
    stdout: String

export fn make_case(name: String, stdin: String, stdout: String) GenCase:
    return GenCase(name.clone(), stdin.clone(), stdout.clone())

# The directory of challenge `id`.
export fn dir(id: String) String: "{root()}/challenges/{id}"

# Writes examples/cases.json and hidden/cases.json for challenge `id` as `json.dumps(cases, indent=1)` does.
export fn write_cases(id: String, examples: List[GenCase], hidden: List[GenCase]) Unit:
    let names = hidden.map(fn c: c.name.clone())
    if names.distinct().length() != names.length(): panic("duplicate case names")

    write_text("{dir(id)}/examples/cases.json", dumps_data(examples, 1) + "\n")
    write_text("{dir(id)}/hidden/cases.json", dumps_data(hidden, 1) + "\n")

# The Go oracle of a large challenge, built from `oracle/*.ref`; returns the path of the executable.
export fn build_oracle(id: String) String:
    let tmp = temporary_directory("msbench-oracle-").get()
    let sources = bash("ls oracle/*.ref", dir(id), 10, "").out.trim().split("\n")
    for source in sources:
        let name = source.split("/").last().get("")
        copy_file("{dir(id)}/{source}", "{tmp}/{name.slice(0, name.length() - 4).get("")}", replace: true).get()
    write_file("{tmp}/go.mod", "module oracle\n\ngo 1.21\n", replace: true).get()
    let built = bash("go build -o oracle .", tmp, 600, "")
    if built.code != 0: panic("go build failed: {built.err}")

    return "{tmp}/oracle"

# The oracle's output for `stdin`.
export fn solve_with(oracle: String, stdin: String) String:
    let ran = bash("\"{oracle}\"", ".", 120, stdin)
    if ran.code != 0: panic("oracle failed (exit {ran.code}): {ran.err.take(500)}")

    return ran.out
