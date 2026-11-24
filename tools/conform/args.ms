// The command line of tools/conform.ms: `--flag value`, `--flag=value` and bare
// switches.

// Flags that take no value.
SWITCHES List[String] := [
	"quiet", "no-stable-check", "prune", "only-missing", "help", "strict", "no-docs",
	"no-tree", "no-twins"
]

export type Args {
	values Map[String, List[String]]
	positional List[String]
	problem String
}

export fn parse_args(words List[String]) Args {
	var args = Args(values: Map[String, List[String]](), positional: [], problem: "")
	var at = 0

	while at < words.length() {
		word := words[at].clone()
		at += 1

		if not word.starts_with("--") {
			args.positional.append(word.clone())
			continue
		}

		flag := word.slice(2, word.length())
		equals := flag.index_of("=") or (-1)
		var name = flag.clone()
		var value = ""

		if equals >= 0 {
			name = flag.slice(0, equals).clone()
			value = flag.slice(equals + 1, flag.length()).clone()
		} else if not SWITCHES.contains(flag) {
			if at >= words.length() {
				args.problem = f"--{flag} needs a value"
				return args
			}

			value = words[at].clone()
			at += 1
		}

		var held = (args.values.get(name) or List[String]()).clone()
		held.append(value.clone())
		args.values.add(name.clone(), held)
	}

	return args
}

export fn has(args Args, flag String) Bool {
	return args.values.get(flag) != null
}

// The last value of `flag`, or `fallback`.
export fn one(args Args, flag String, fallback String) String {
	held := args.values.get(flag)
	if held != null {
		if held.length() > 0 { return held[held.length() - 1].clone() }
	}
	return fallback.clone()
}

// Every value of a repeatable flag; each value may be comma separated.
export fn many(args Args, flag String) List[String] {
	var out = List[String]()
	for value in (args.values.get(flag) or List[String]()) {
		for part in value.split(",") {
			if part.trim() != "" { out.append(part.trim().clone()) }
		}
	}
	return out
}

export fn number(args Args, flag String, fallback Int) Int {
	return one(args, flag, "").parse_int() or fallback
}
