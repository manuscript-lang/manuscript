// Data loading shared by the runner: challenges, languages, pricing. Paths are relative
// to the repository root, where every command in README.md runs.
import (
	panic from "@std/core.ms",
	JsonValue, parse from "@std/data/json.ms",
	access, list, read_file from "@std/os/fs.ms",

	env from "../lib/text.ms",
)

// `bench/agent` when the command runs from the repository root, `.` when it runs inside this directory (as `ms test` does).
export fn root() String {
	if access("bench/agent/languages.json", 0).is_ok() { return "bench/agent" }
	return "."
}

// Documentation for the Manuscript context bundle comes from here; override to pin a
// different checkout.
export fn repo() String => env(
	"MSBENCH_REPO",
	if root() == "." { "../.." } else { "." },
)

// One input and the exact output expected for it.
export type Case {
	stdin, stdout String
	name String = "?"
}

type Meta {
	title, category String
	tier Int
	timeout_s Int = 5
	// Agent wall-clock limit for this challenge when longer than the run's; 0 for none.
	agent_timeout_s Int = 0
}

export type Challenge {
	id, title, category String
	tier, timeout_s, agent_timeout_s Int
	dir String
}

fn Challenge.spec() String => (
	read_file(f"{self.dir}/spec.md").wait().get().decode_utf8()
	or ""
)

// `which` is `examples` (visible to the agent) or `hidden`.
fn Challenge.cases(which String) List[Case] {
	text := (
		read_file(f"{self.dir}/{which}/cases.json").wait().get().decode_utf8()
		or ""
	)
	return parse[List[Case]](text).get_or([])
}

fn Challenge.solution(lang String) String => f"{self.dir}/solutions/{lang}"

// A language the benchmark can be solved in, as `languages.json` describes it.
export type Lang {
	id, name, solution, build, run, notes, template String
	context List[String]
	// Shell command run in the new workspace, such as installing the agent skill.
	setup String
	// Shell command that prints the diagnostic codes of the last build, one per line.
	codes String
	// Shell command applying the language's machine-applicable fixes in place; empty
	// when it has none.
	fix String
	// Shell command that prints the toolchain's version.
	version String
}

// The extension of the solution file, such as `.ms`.
fn Lang.suffix() String {
	base := self.solution.split("/").last() or ""
	at := base.last_index_of(".")
	if at != null { return base.slice(at, base.length()) }

	return ""
}

// The file name of the reference solution, such as `main.ms.ref`.
fn Lang.reference() String => f"{(self.solution.split("/").last() or "")}.ref"

fn text_of(file String) String {
	return read_file(file).wait().get().decode_utf8() or ""
}

fn field(doc JsonValue, key String) String {
	value := doc.get(key)
	if value != null { return value.as_string() or "" }

	return ""
}

// Challenges whose id equals, or starts with, one of `ids` (all when `ids` is empty),
// in id order.
export fn load_challenges(ids List[String]) List[Challenge] {
	var out = List[Challenge]()
	var names = List[String]()
	for entry in list(f"{root()}/challenges").get_or([]) {
		names.append(entry.name.clone())
	}

	for name in names.sorted() {
		dir := f"{root()}/challenges/{name}"
		meta_text := read_file(f"{dir}/challenge.json").wait()
		if not meta_text.is_ok() { continue }

		m := parse[Meta](meta_text.get().decode_utf8() or "").get_or(
			Meta("", "", 0, 5, 0)
		)
		wanted := (
			ids.is_empty()
			or ids.any(i => (name == i or name.starts_with(f"{i}-")))
		)
		if wanted {
			out.append(
				Challenge(
					name.clone(),
					m.title.clone(),
					m.category.clone(),
					m.tier,
					m.timeout_s,
					m.agent_timeout_s,
					dir,
				)
			)
		}
	}

	return out
}

// Languages named in `ids` (all when empty), in file order; an unknown id stops the
// program.
export fn load_languages(ids List[String]) List[Lang] {
	doc := parse(text_of(f"{root()}/languages.json")).get_or(JsonValue.Null)
	var out = List[Lang]()
	var known = List[String]()

	for entry in (doc.as_map() or Map[String, JsonValue]()).entries() {
		known.append(entry.key.clone())
		if not ids.is_empty() and not ids.contains(
			entry.key
		) { continue }

		d := entry.value
		var context = List[String]()
		items := d.get("context")
		if items != null {
			for item in (items.as_list() or []) {
				context.append(item.as_string() or "")
			}
		}

		var template = entry.key.clone()
		t := d.get("template")
		if t != null { template = t.as_string() or entry.key }
		out.append(
			Lang(
				entry.key.clone(),
				field(d, "name"),
				field(d, "solution"),
				field(d, "build"),
				field(d, "run"),
				field(d, "notes"),
				template,
				context,
				field(d, "setup"),
				field(d, "codes"),
				field(d, "fix"),
				field(d, "version"),
			)
		)
	}

	unknown := ids.filter(i => not known.contains(i))
	if not unknown.is_empty() { panic(f"unknown languages: {unknown.join(", ")}") }
	return out
}

// Estimated USD from `pricing.json`; `tokens_in` excludes cached tokens.
export fn cost_from_tokens(tokens_in, cached, tokens_out Int, model String) Float {
	table := parse(text_of(f"{root()}/pricing.json")).get_or(JsonValue.Null)
	var p = table.get("default") or JsonValue.Null
	own := table.get(model)
	if own != null { p = own.clone() }

	input := (p.get("input") or JsonValue.Null).as_float() or 0.0
	cached_input := (p.get("cached_input") or JsonValue.Null).as_float() or 0.0
	output := (p.get("output") or JsonValue.Null).as_float() or 0.0
	return (
		(
			tokens_in.to_float() * input
			+ cached.to_float() * cached_input
			+ tokens_out.to_float() * output
		)
		/ 1000000.0
	)
}
