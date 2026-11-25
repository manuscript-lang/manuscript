// ms: allow_effect std.console.write
// ms: allow_effect std.env.read
// ms: allow_effect std.fs.delete
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run
// ms: allow_effect std.system.read

// `conform fuzz-gen` and `conform fuzz`: generated programs written into the corpus, or run under two ms
// binaries and compared.
import (
	CopyOptions, copy, create_directory, temporary, write_file from "@std/os/fs.ms",
	system_info from "@std/os/system.ms",

	tool_ms from "../lib.ms",
	Args, number, one from "./args.ms",
	Meta, render_meta from "./corpus.ms",
	differing from "./diff.ms",
	Generated, program, syntax_error, type_error from "./fuzz.ms",
	filter_of, select from "./select.ms",
	sorted_unique from "./tags.ms",
)

type Kind {
	name, dir, phase String
}

fn kind_of(args Args) Kind {
	name := one(args, "kind", "run")
	if name == "type" { return Kind(name: "type", dir: "fuzz/types", phase: "check") }
	if name == "syntax" {
		return Kind(name: "syntax", dir: "fuzz/syntax", phase: "parse")
	}

	return Kind(name: name.clone(), dir: "fuzz/run", phase: "run")
}

fn generate(kind Kind, seed Int) Generated {
	if kind.name == "type" { return type_error(seed) }
	if kind.name == "syntax" { return syntax_error(seed) }

	return program(seed)
}

// `A..B` as the half-open seed range; (0, 0) with a problem when it does not parse.
fn seed_range(args Args) List[Int] {
	text := one(args, "seeds", "0..100")
	at := text.index_of("..") or (-1)
	if at < 0 { return [-1, -1] }

	low := text.slice(0, at).parse_int() or (-1)
	high := text.slice(at + 2, text.length()).parse_int() or (-1)
	return [low, high]
}

fn padded(seed Int) String {
	text := f"{seed}"
	if text.length() >= 4 { return text }

	return "0".repeat(4 - text.length()) + text
}

// Writes `seed-NNNN.ms` for each seed into `dir`; returns how many.
fn write_generated(dir String, kind Kind, low, high Int) Int {
	void create_directory(dir.clone(), recursive: true).get()

	var written = 0

	for seed in low..high {
		generated := generate(kind, seed)
		var tags = generated.tags.clone()
		if kind.phase == "run" { tags.append("stdlib-io") }

		meta := Meta(
			tags: sorted_unique(tags),
			phase: kind.phase.clone(),
			args: [],
			timeout: 0,
			entry: "",
			origin: f"ms-conform fuzz-gen --kind {kind.name} seed {seed}",
			deterministic: true,
		)
		write_file(
			f"{dir}/seed-{padded(seed)}.ms",
			render_meta(meta) + generated.source,
			replace: true,
		)
			.wait()
			.get()
		written += 1
	}

	return written
}

export fn fuzz_gen(root, corpus String, args Args) Int {
	kind := kind_of(args)
	range := seed_range(args)

	if range[0] < 0 or range[1] < range[0] {
		print("conform fuzz-gen: --seeds wants A..B")
		return 64
	}

	dir := f"{corpus}/{kind.dir}"
	n := write_generated(dir, kind, range[0], range[1])
	print(
		f"wrote {n} fixtures to {dir}; record them with `ms run tools/conform-run.ms -- --record {kind.dir}/`"
	)
	return 0
}

export fn fuzz(root String, args Args) Int {
	kind := kind_of(args)
	range := seed_range(args)

	if range[0] < 0 or range[1] < range[0] {
		print("conform fuzz: --seeds wants A..B")
		return 64
	}

	oracle := one(args, "oracle", "")

	if oracle == "" {
		print("conform fuzz: --oracle PATH names the reference ms")
		return 64
	}

	candidate := one(args, "ms", tool_ms(root))
	build_type := one(args, "build-type", "Release")
	scratch := temporary("ms-conform-fuzz-").get()
	dir := f"{scratch.path()}/fixtures"
	count := write_generated(dir, kind, range[0], range[1])
	print(f"fuzzing {count} {kind.name} programs: oracle {oracle} vs {candidate}")

	chosen := select(dir, filter_of(args))
	different := differing(
		oracle,
		build_type,
		candidate,
		build_type,
		chosen,
		number(args, "jobs", system_info().cpu_count),
	)
	save := one(args, "save", "")

	if save != "" and not different.is_empty() {
		void create_directory(save.clone(), recursive: true).get()
		for id in different {
			void copy(f"{dir}/{id}.ms", f"{save}/{id}.ms", CopyOptions(replace: true)).get()
		}
	}

	for id in different { print(f"DIFF {id}") }
	print(
		f"{chosen.length()} programs: {chosen.length() - different.length()} same, {different.length()} differ"
	)
	if different.is_empty() { return 0 }

	return 1
}
