# Export agent-bench challenges as Harbor tasks (one per challenge x language).
#
#     ms run bench/agent/export_harbor.ms -- --out /tmp/agent-bench-tasks [--challenges c01,c02] [--languages ms,go]
#         [--ms-binary ./ms] [--agent-timeout 900]
#
# Run from the repository root. Each task directory: instruction.md, task.toml,
# environment/{Dockerfile,workspace/,ms}, tests/{test.sh,grade.ms,cases.json,...}, solution/solve.sh. Hidden cases
# live only in tests/, which Harbor uploads at verification time. The verifier runs `ms` inside the task, so every
# image carries the binary given by --ms-binary. The output is generated; do not commit it.
import Flag, FlagKind, command from "@std/cli.ms"
import chmod, copy_file, create_directory, remove, stat from "@std/fs.ms"
import JsonValue from "@std/json.ms"
import stderr, stdout from "@std/io.ms"
import arguments from "@std/process.ms"
import Challenge, Lang, root, load_challenges, load_languages from "./core/model.ms"
import make_workspace from "./core/workspace.ms"
import dumps from "./lib/pyjson.ms"
import read_text, write_text from "./lib/text.ms"

type Options:
    out: String
    challenges: String = ""
    languages: String = ""
    ms_binary: String = ""
    agent_timeout: Int = 900

fn base_image(lang_id: String) String:
    if lang_id == "ts": return "node:22-bookworm"
    if lang_id == "go": return "golang:1.25-bookworm"
    if lang_id == "rust": return "rust:1-bookworm"

    return "ubuntu:24.04"

fn dockerfile(lang_id: String) String:
    let install = "apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git && rm -rf /var/lib/apt/lists/*"
    return [
        "FROM {base_image(lang_id)}", "RUN {install}", "COPY ms /usr/local/bin/ms",
        "WORKDIR /app", "COPY workspace /app", ""
    ].join("\n")

fn task_toml(name: String, ch: Challenge, agent_timeout: Int) String:
    return read_text("{root()}/harbor/task.toml.tmpl").replace(
        "\{name\}", name
    ).replace("\{title\}", ch.title).replace("\{category\}", ch.category).replace(
        "\{tier\}", "{ch.tier}"
    ).replace("\{agent_timeout\}", "{agent_timeout}.0")

fn quote(text: String) String: dumps(JsonValue.StringValue(text.clone()), 0)

fn put(from: String, to: String) Unit:
    create_directory(
        to.split("/").take(to.split("/").length() - 1).join("/"), recursive: true
    ).get()
    copy_file(from, to, replace: true).get()

fn export_one(
    ch: Challenge,
    lang: Lang,
    out: String,
    ms_binary: String,
    agent_timeout: Int
) Unit:
    let name = "{ch.id}-{lang.id}"
    let d = "{out}/{name}"
    remove(d, recursive: true).to_optional()
    create_directory("{d}/environment", recursive: true).get()

    let prompt = make_workspace(ch, lang, "{d}/environment/workspace")
    write_text("{d}/instruction.md", prompt + "\n\n---\n\n" + ch.spec())
    write_text("{d}/task.toml", task_toml(name, ch, agent_timeout))
    write_text("{d}/environment/Dockerfile", dockerfile(lang.id))

    if ms_binary == "":
        (
            stderr()
            .write(
                "  note: {name} needs --ms-binary for its Docker image (the verifier runs `ms`; the local-process env uses PATH)\n"
            )
            .get()
        )
    else:
        put(ms_binary, "{d}/environment/ms")

    # The verifier and the modules it imports keep their relative layout under /tests.
    for file in ["grade.ms", "core/model.ms", "core/codetokens.ms", "lib/text.ms"]:
        put("{root()}/{file}", "{d}/tests/{file}")
    put("{ch.dir}/hidden/cases.json", "{d}/tests/cases.json")
    write_text(
        "{d}/tests/test.sh",
        "#!/bin/bash\nms run /tests/grade.ms -- /tests/cases.json {quote(lang.build)} {quote(lang.run)} {ch.timeout_s} {lang.suffix()}\n"
    )

    let reference = "{ch.solution(lang.template)}/{lang.reference()}"

    if stat(reference, true).is_ok():
        put(reference, "{d}/solution/reference")
        write_text(
            "{d}/solution/solve.sh",
            "#!/bin/bash\nmkdir -p \"$(dirname /app/{lang.solution})\"\ncp \"$(dirname \"$0\")/reference\" /app/{lang.solution}\n"
        )
    else:
        # Large challenges are oracle-validated in Go only; the oracle agent has nothing to apply.
        write_text(
            "{d}/solution/solve.sh",
            "#!/bin/bash\necho 'no reference solution for this language' >&2\nexit 1\n"
        )

    chmod("{d}/tests/test.sh", 493).get()
    chmod("{d}/solution/solve.sh", 493).get()

fn split_ids(text: String) List[String]:
    return text.split(",").filter(fn x: not x.is_empty())

fn run_export(o: Options) Int!:
    create_directory(o.out, recursive: true).get()

    var n = 0

    for ch in load_challenges(split_ids(o.challenges)):
        for lang in load_languages(split_ids(o.languages)):
            export_one(ch, lang, o.out, o.ms_binary, o.agent_timeout)
            n += 1

    stdout().write("exported {n} tasks to {o.out}\n").get()
    return ok(0)

export fn main() Int:
    let root = command[Options](
        name: "export_harbor.ms",
        about: "Export agent-bench challenges as Harbor tasks (one per challenge x language)",
        flags: [
            Flag("out", required: true), Flag("challenges", default: ""),
            Flag("languages", default: ""), Flag("ms-binary", default: ""),
            Flag("agent-timeout", FlagKind.Int, default: "900")
        ],
        run: fn o: run_export(o)
    )
    return root.execute(arguments())
