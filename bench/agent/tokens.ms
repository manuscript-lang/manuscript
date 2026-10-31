# Source size in LLM tokens (tiktoken o200k_base) per language over the reference solutions.
#
# Usage (from the repository root): ms run bench/agent/tokens.ms   # needs `pip install tiktoken`
# The reference table shows how verbose each language is when the same program is written by hand;
# agent-written sizes come from `llm_tokens` in results/runs.jsonl (see README).
import glob from "@std/fs.ms"
import stdout, stderr from "@std/io.ms"
import root, load_challenges from "./core/model.ms"
import bash from "./lib/text.ms"

let LANGS = ["ts", "rust", "go", "ms"]

# Token counts of `paths` from one tiktoken process; none when tiktoken is unavailable.
fn count_tokens(paths: List[String]) List[Int]?:
    let program = "import sys, tiktoken; e = tiktoken.get_encoding('o200k_base'); [print(len(e.encode(open(p, encoding='utf-8').read()))) for p in sys.argv[1:]]"
    let quoted = paths.map(fn p: "'{p}'").join(" ")
    let ran = bash("python3 -c \"{program}\" {quoted}", ".", 600, "")
    if ran.code != 0: return none

    let counts = ran.out.trim().split("\n").map(fn n: n.parse_int().get(0))
    return counts

fn ratio(top: Int, bottom: Int) String: (top.to_float() / bottom.to_float()).to_fixed(2)

export fn main() Int:
    # Each challenge with a reference solution in every language, as a row of file paths in LANGS order.
    var names = List[String]()
    var paths = List[String]()
    for ch in load_challenges([]):
        var row = List[String]()
        for lang in LANGS:
            let refs = glob("{ch.dir}/solutions/{lang}", "*.ref", none).get([])
            if not refs.is_empty(): row.append("{ch.dir}/solutions/{lang}/{refs[0]}")
        if row.length() == LANGS.length():
            names.append(ch.id.clone())
            paths = paths.concat(row)
    let counts = count_tokens(paths)
    if counts.is_none():
        stderr().write("tokens.ms needs python3 with tiktoken installed (pip install tiktoken)\n").get()
        return 1

    let all = counts.get([])
    var totals = [0, 0, 0, 0]
    var out = "challenge".pad_end(26, " ") + LANGS.map(fn l: l.pad_start(8, " ")).join("") + "  ms/ts\n"
    for i in 0..names.length():
        let row = all.slice(i * 4, i * 4 + 4).get([])
        for j in 0..4: totals[j] = totals[j] + row[j]
        out = out + names[i].pad_end(26, " ") + row.map(fn n: "{n}".pad_start(8, " ")).join("") + "  {ratio(row[3], row[0])}\n"
    out = out + "total".pad_end(26, " ") + totals.map(fn n: "{n}".pad_start(8, " ")).join("") + "  {ratio(totals[3], totals[0])}\n"
    out = out + "ms/rust {ratio(totals[3], totals[1])}\n"
    stdout().write(out).get()
    return 0
