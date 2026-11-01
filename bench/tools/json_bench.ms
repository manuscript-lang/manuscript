# Compares @std/json against Node (V8) and Rust's serde_json on standard documents (bench/perf/json).
# Usage: ms run bench/tools/json_bench.ms   (NAMES="twitter canada" selects documents; MS picks the compiler)
# The corpora are downloaded into bench/perf/json/data (not committed).
import Invalid, capture, env, exists, finish, jbool, jint, jlist, jobject, jstr, left, ms_binary, must, output_of, right, run_in, write_text from "./lib.ms"
import create_directory from "@std/os/fs.ms"
import JsonValue, stringify from "@std/data/json.ms"

let DATA = "bench/perf/json/data"

# The small-message document, built as a value because a JSON literal needs every quote and brace escaped.
fn small() String:
    var params = Map[String, JsonValue]()
    params.add("name", jstr("worker-7"))
    params.add("args", jlist([jstr("--fast"), jstr("--verbose")]))
    params.add("timeout", JsonValue.NumberValue("1.5"))
    params.add("retry", jbool(true))
    params.add("env", JsonValue.Null)

    var user = Map[String, JsonValue]()
    user.add("id", jint(99))
    user.add("name", jstr("Ada Lovelace"))
    user.add("email", jstr("ada@example.com"))

    var doc = Map[String, JsonValue]()
    doc.add("id", jint(12345))
    doc.add("type", jstr("request"))
    doc.add("method", jstr("tasks.spawn"))
    doc.add("params", jobject(params))
    doc.add("tags", jlist([jstr("a"), jstr("b"), jstr("c")]))
    doc.add("user", jobject(user))
    return stringify(jobject(doc), none, none).get("") + "\n"

fn fetch_corpora() Result[Unit, Invalid]:
    let _dir = create_directory(DATA, recursive: true)

    for f in ["twitter", "canada", "citm_catalog"]:
        if exists("{DATA}/{f}.json"): continue

        let url = "https://raw.githubusercontent.com/miloyip/nativejson-benchmark/master/data/{f}.json"
        let _ = try must(
            "curl {f}", capture("curl", ["-sSfL", "-o", "{DATA}/{f}.json", url])
        )

    # Small messages: the shape worker threads and RPC exchange.
    if not exists("{DATA}/small.json"): write_text("{DATA}/small.json", small())
    return ok(unit)

type Rate:
    nanos: Int
    bytes: Int

# Maps `<doc>\t<op>\t<ns>\t<bytes>` lines to rates.
fn load(text: String) Map[String, Rate]:
    var rows = Map[String, Rate]()

    for line in text.split("\n"):
        let f = line.split("\t")
        if f.length() != 4: continue

        rows.add(
            "{f[0]}\t{f[1]}", Rate(f[2].parse_int().get(1), f[3].parse_int().get(0))
        )

    return rows

fn mbps(r: Rate) Float:
    return r.bytes.to_float() / r.nanos.to_float() * 1000.0

fn run(names: List[String]) Result[String, Error]:
    try fetch_corpora()

    let node = try must(
        "node", capture("node", ["bench/perf/json/node.js"].concat(names))
    )
    let ms = try must(
        "ms run",
        capture(
            ms_binary(), ["run", "bench/perf/json/ms.toml", "--"].concat(names)
        )
    )
    let rust = try must(
        "cargo run",
        run_in(
            "bench/perf/json/rust", "cargo",
            ["run", "--release", "--quiet", "--"].concat(names)
        )
    )
    let n = load(node)
    let r = load(rust)
    let m = load(ms)
    let revision = output_of("git", ["rev-parse", "--short", "HEAD"]).trim()
    let host = output_of("uname", ["-sm"]).trim()
    var rows = [
        "node {output_of("node", ["--version"]).trim()}, {revision}, {host}",
        left("doc", 14) + left("op", 11) + right("node MB/s", 10) + right(
            "serde MB/s", 11
        ) + right("ms MB/s", 10) + right("ms/node", 9) + right("ms/serde", 10)
    ]

    for key in n.keys():
        if not (m.contains(key) and r.contains(key)): continue

        let f = key.split("\t")
        let nr = n.get(key).get(Rate(1, 0))
        let rr = r.get(key).get(Rate(1, 0))
        let mr = m.get(key).get(Rate(1, 0))
        rows.append(
            left(f[0], 14) + left(f[1], 11) + right(
                mbps(nr).to_fixed(0), 10
            ) + right(mbps(rr).to_fixed(0), 11) + right(
                mbps(mr).to_fixed(0), 10
            ) + right(
                (nr.nanos.to_float() / mr.nanos.to_float()).to_fixed(2), 8
            ) + "x" + right(
                (rr.nanos.to_float() / mr.nanos.to_float()).to_fixed(2), 9
            ) + "x"
        )

    return ok(rows.join("\n"))

export fn main() Int:
    let names = env("NAMES", "small twitter canada citm_catalog records").split(
        " "
    ).filter(fn s: (s != ""))
    return finish(run(names))
