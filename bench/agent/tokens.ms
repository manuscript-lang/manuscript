// Source size in LLM tokens (tiktoken o200k_base) per language over the reference
// solutions.
//
// Usage (from the repository root): ms run bench/agent/tokens.ms # needs
// `pip install tiktoken` The reference table shows how verbose each language is when
// the same program is written by hand; agent-written sizes come from `llm_tokens` in
// results/runs.jsonl (see README).
import (
	stderr, stdout from "@std/io/io.ms",
	GlobOptions, glob from "@std/os/fs.ms",

	load_challenges from "./core/model.ms",
	bash from "./lib/text.ms",
)

LANGS := ["ts", "rust", "go", "ms"]

// Token counts of `paths` from one tiktoken process; none when tiktoken is unavailable.
fn count_tokens(paths List[String]) List[Int]? {
	program := "import sys, tiktoken; e = tiktoken.get_encoding('o200k_base'); [print(len(e.encode(open(p, encoding='utf-8').read()))) for p in sys.argv[1:]]"
	quoted := paths.map(p => f"'{p}'").join(" ")
	ran := bash(f"python3 -c \"{program}\" {quoted}", ".", 600, "")
	if ran.code != 0 { return null }

	counts List[Int] := ran.out.trim().split("\n").map(n => n.parse_int() or 0)
	return counts
}

fn ratio(top Int, bottom Int) String => (top.to_float() / bottom.to_float()).to_fixed(2)

fn main() Int {
	// Each challenge with a reference solution in every language, as a row of file
	// paths in LANGS order.
	var names = List[String]()
	var paths = List[String]()

	for ch in load_challenges([]) {
		var row = List[String]()

		for lang in LANGS {
			refs := glob(f"{ch.dir}/solutions/{lang}", GlobOptions(patterns: ["*.ref"])).get_or(
				[]
			)
			if not refs.is_empty() {
				row.append(f"{ch.dir}/solutions/{lang}/{refs[0].path}")
			}
		}

		if row.length() == LANGS.length() {
			names.append(ch.id.clone())
			paths = paths.concat(row)
		}
	}

	counts := count_tokens(paths)

	if counts == null {
		(
			stderr()
			.write(
				"tokens.ms needs python3 with tiktoken installed (pip install tiktoken)\n"
			)
			.get()
		)
		return 1
	}

	all := counts
	var totals = [0, 0, 0, 0]
	var out = (
		"challenge".pad_end(26, " ")
		+ LANGS.map(l => l.pad_start(8, " ")).join("")
		+ "  ms/ts\n"
	)

	for i in 0..names.length() {
		row := all.slice(i * 4, i * 4 + 4).get_or([])
		for j in 0..4 { totals[j] += row[j] }
		out = (
			out
			+ names[i].pad_end(26, " ")
			+ row.map(n => f"{n}".pad_start(8, " ")).join("")
			+ f"  {ratio(row[3], row[0])}\n"
		)
	}

	out = (
		out
		+ "total".pad_end(26, " ")
		+ totals.map(n => f"{n}".pad_start(8, " ")).join("")
		+ f"  {ratio(totals[3], totals[0])}\n"
	)
	out += f"ms/rust {ratio(totals[3], totals[1])}\n"
	stdout().write(out).get()
	return 0
}
