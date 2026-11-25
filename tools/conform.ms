// ms: allow_effect std.console.write
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write

// The conformance corpus commands that are not a replay: `list`, `stats`, `lint`,
// `retag`, `diff`,
// `fuzz-gen`, `fuzz` and `harvest`. The replay and recording of expectations is tools/conform-run.ms.
// Usage: ms run tools/conform.ms -- <command> [options]; `--help` lists them. MS names
// the ms under test (default .artifacts/build/ci/src/cli/ms); `--corpus DIR` names the
// fixtures directory (default tests/conformance/fixtures).
import (
	JsonValue, parse from "@std/data/json.ms",
	arguments, working_directory from "@std/os/env.ms",
	GlobOptions, glob, write_file from "@std/os/fs.ms",

	Args, has, one, parse_args from "./conform/args.ms",
	candidate_ids, parse_meta, read_text, render_meta from "./conform/corpus.ms",
	run_diff from "./conform/diff.ms",
	fuzz, fuzz_gen from "./conform/fuzz_commands.ms",
	harvest from "./conform/harvest.ms",
	Filter, filter_of, select from "./conform/select.ms",
	imports_of, tag_allowed, tier_of from "./conform/tags.ms",
)

USAGE String := """
conform: corpus commands (the replay is tools/conform-run.ms)

usage: ms run tools/conform.ms -- <command> [options]

commands:
  list      list fixtures (id, phase, tags)
  stats     count fixtures per phase and tag
  lint      validate fixture metadata and expectation files
  retag     recompute tier-* tags on every fixture from its imports
  diff      run two ms binaries on the corpus and compare them directly:
            --ms-a PATH --ms-b PATH [--build-type-a T] [--build-type-b T]
  fuzz-gen  write deterministic generated fixtures into the corpus:
            --kind run|type|syntax --seeds A..B
  fuzz      differential fuzzing: generate programs, run --oracle and --ms, compare:
            --oracle PATH --kind K --seeds A..B [--save DIR]
  harvest   turn repository sources and documentation fences into fixtures:
            [--no-docs] [--no-tree] [--no-twins] (then record with `ms run tools/conform-run.ms -- --record --prune`)

selection (list, stats, diff):
  --tag T[,T]   only fixtures with any of these tags (repeatable)
  --exclude-tag T   skip fixtures with this tag
  --phase P[,P]   parse, check, run or test
  --id TEXT   only fixtures whose id contains TEXT
  --shard I/N   every Nth fixture starting at I (0-based)
  --jobs N   parallel fixtures (default: every processor, at most 8)
"""

fn corpus_of(root String, args Args) String {
	return one(args, "corpus", f"{root}/tests/conformance/fixtures")
}

fn list_command(corpus String, filter Filter) Int {
	for fx in select(corpus, filter) {
		print(f"{fx.id}\t{fx.phase}\t{fx.tags.join(",")}")
	}
	return 0
}

fn count_of(counts Map[String, Int], key String) Int {
	return counts.get(key) or 0
}

fn stats_command(corpus String, filter Filter) Int {
	chosen := select(corpus, filter)
	phases := ["parse", "check", "run", "test"]
	var by_phase = Map[String, Int]()
	var by_tag = Map[String, Int]()
	var tag_names = List[String]()

	for fx in chosen {
		by_phase.add(fx.phase.clone(), count_of(by_phase, fx.phase) + 1)

		for tag in fx.tags {
			if not tag_names.contains(tag) {
				tag_names.append(tag.clone())
			}

			key := f"{tag}|{fx.phase}"
			by_tag.add(key.clone(), count_of(by_tag, key) + 1)
		}
	}

	tag_names.sort()
	print(f"{chosen.length()} fixtures")
	print(f"| tag | total | {phases.join(" | ")} |")
	print("|---|---:|---:|---:|---:|---:|")

	var row = f"| all | {chosen.length()} |"
	for phase in phases { row += f" {count_of(by_phase, phase)} |" }
	print(row)

	for tag in tag_names {
		var total = 0
		var cells = ""

		for phase in phases {
			n := count_of(by_tag, f"{tag}|{phase}")
			total += n
			cells += f" {n} |"
		}

		print(f"| {tag} | {total} |{cells}")
	}

	return 0
}

// Problems with fixture metadata and expectation files, one per line.
fn lint_command(corpus String) Int {
	var problems = List[String]()
	var known_ids = List[String]()
	var sidecars = List[String]()
	var seen = Map[String, Bool]()
	everything := select(corpus, filter_of(parse_args([])))

	for fx in everything {
		known_ids.append(fx.id.clone())
		if seen.get(
			fx.id
		) != null { problems.append(f"{fx.id}: duplicate id") }
		seen.add(fx.id.clone(), true)
		if fx.tags.is_empty() {
			problems.append(f"{fx.id}: no tags")
		}
		for tag in fx.tags {
			if not tag_allowed(tag) {
				problems.append(f"{fx.id}: unknown tag {tag}")
			}
		}
		if fx.phase == "parse" and fx.is_dir {
			problems.append(f"{fx.id}: parse fixtures must be single files")
		}
		if not fx.is_dir { sidecars.append(fx.sidecar.clone()) }

		text := read_text(fx.sidecar)

		if text == "" {
			problems.append(f"{fx.id}: no recorded expectation at {fx.sidecar}")
			continue
		}

		document := parse(text).get_or(JsonValue.Null)

		if document == JsonValue.Null {
			problems.append(f"{fx.id}: expectation is not JSON")
			continue
		}

		recorded := document.get("phase")
		if recorded == null or (recorded.as_string() or "") != fx.phase {
			problems.append(f"{fx.id}: expectation phase differs from fixture")
		}
		if document.get("expected") == null {
			problems.append(f"{fx.id}: expectation has no `expected` value")
		}
	}

	for id in candidate_ids(corpus) {
		if not known_ids.contains(id) {
			problems.append(f"{id}: no usable `// conform: phase=` header")
		}
	}

	var project_dirs = List[String]()
	for entry in glob(corpus, GlobOptions(patterns: ["**/conform.meta"])).get_or([]) {
		project_dirs.append(
			entry.path.slice(
				0,
				entry.path.length() - "conform.meta".length(),
			).clone()
		)
	}

	for entry in glob(corpus, GlobOptions(patterns: ["**/*.expected.json"])).get_or(
		[]
	) {
		var inside = false
		for dir in project_dirs {
			if entry.path.starts_with(
				dir
			) { inside = true }
		}
		if inside { continue }

		if not sidecars.contains(f"{corpus}/{entry.path}") {
			problems.append(f"{entry.path}: expectation without a fixture")
		}
	}

	for problem in problems { print(problem) }
	print(f"{everything.length()} fixtures, {problems.length()} problems")
	if problems.is_empty() { return 0 }

	return 1
}

// The text of a project directory's sources, for its import tier.
fn project_text(dir String) String {
	var text = ""
	for entry in glob(dir, GlobOptions(patterns: ["**/*.ms", "ms.toml"])).get_or([]) {
		text += read_text(f"{dir}/{entry.path}") + "\n"
	}
	return text
}

fn retag_command(corpus String) Int {
	var changed = 0

	for fx in select(corpus, filter_of(parse_args([]))) {
		meta_path := if fx.is_dir { f"{fx.path}/conform.meta" } else { fx.path.clone() }
		source := read_text(meta_path)
		if source == "" { continue }

		text := if fx.is_dir { project_text(fx.path) } else { source.clone() }
		var meta = parse_meta(source)
		var tags = List[String]()
		for tag in meta.tags {
			if not tag.starts_with("tier-") {
				tags.append(tag.clone())
			}
		}
		tags.append(tier_of(imports_of(text)))
		tags.sort()

		var unique = List[String]()
		for tag in tags {
			if unique.is_empty() or unique[unique.length() - 1] != tag {
				unique.append(tag.clone())
			}
		}
		if unique == meta.tags { continue }

		meta.tags = unique

		var out = render_meta(meta)

		if not fx.is_dir {
			var lines = source.split("\n")
			var skipped = 0
			while (
				skipped < lines.length()
				and lines[skipped].starts_with("// conform:")
			) { skipped += 1 }
			out += lines.slice(skipped, lines.length()).get_or([]).join("\n")
		}

		write_file(meta_path, out, replace: true).wait().get()
		changed += 1
	}

	print(f"{changed} fixtures retagged")
	return 0
}

fn main() Int {
	words := arguments()

	if words.is_empty() or words[0] == "--help" or words[0] == "help" {
		print(USAGE)
		return if words.is_empty() { 64 } else { 0 }
	}

	command := words[0].clone()
	args := parse_args(words.slice(1, words.length()).get_or([]))

	if args.problem != "" {
		print(f"conform: {args.problem}")
		return 64
	}

	if has(args, "help") {
		print(USAGE)
		return 0
	}

	root := working_directory().get()
	corpus := corpus_of(root, args)
	filter := filter_of(args)

	if filter.problem != "" {
		print(f"conform: {filter.problem}")
		return 64
	}

	if command == "list" { return list_command(corpus, filter) }
	if command == "stats" { return stats_command(corpus, filter) }
	if command == "lint" { return lint_command(corpus) }
	if command == "retag" { return retag_command(corpus) }
	if command == "diff" { return run_diff(root, corpus, filter, args) }
	if command == "fuzz-gen" { return fuzz_gen(root, corpus, args) }
	if command == "fuzz" { return fuzz(root, args) }
	if command == "harvest" { return harvest(root, corpus, args) }

	print(f"conform: unknown command {command}; try --help")
	return 64
}
