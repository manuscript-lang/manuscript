// The agent skill teaches executable, versioned Manuscript: its examples check clean,
// its pages are reachable and substantive, its server example is the tested fixture,
// its manifests are accepted, and each common mistake fails as stated. The generated
// call and module tables are checked by src/ms/skill_calls.ms.
import (
	JsonValue, parse from "@std/data/json.ms",
	create_directory, remove, write_file from "@std/os/fs.ms",
	CommandOutput, run from "@std/os/process.ms",
	expect_equal from "@std/test/test.ms",

	tool_ms from "../lib.ms",
	read_text from "./util.ms",
)

SKILL := "src/ms/data/agent-skill"
MISTAKES := "src/ms/data/mistakes.txt"
SCRATCH := "target/skill-check"
EXAMPLES := 25
MANIFESTS := 6
LATER_STAGES := [
	"no ancestor ms.toml has [workspace] members", "ms.lock has no copy of",
	"ms check: workspace member"
]

// The text of a fence that follows `marker` in `page`, up to the closing fence.
fn fence_after(after: String, opening: String) String?:
	if not after.starts_with(opening): return none

	body := after.slice(opening.length(), after.length())
	end := body.index_of("```")
	if end.is_none(): return none

	return body.slice(0, end.get())

// The diagnostics `ms check` reports for `source`, saved as `name` in the scratch
// directory.
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run
fn check_messages(ms: String, name: String, source: String) List[String]:
	path := f"{SCRATCH}/{name}"
	write_file(path, source, replace: true).wait().get()

	out := run(ms, ["check", path, "--json"]).wait()
	if out.is_error(): return [f"cannot run {ms}"]

	doc := parse(out.get().stdout.decode_utf8().get_or("")).get_or(JsonValue.Null)
	var messages = List[String]()

	for entry in doc.get("diagnostics").get_or(JsonValue.Null).as_list().get_or([]):
		message := entry.get("message").get_or(JsonValue.Null).as_string().get_or("")

		// The guide's fragments bind names only to show a rule.
		if not message.contains("is never read"): messages.append(message.clone())

	return messages

// The skill files: the entry first, then the references, as (path, text).
type Page:
	path: String
	text: String

fn pages() List[Page]:
	var out = List[Page]()
	entry := read_text(f"{SKILL}/SKILL.md")
	if entry.is_some(): out.append(Page(path: "SKILL.md", text: entry.get()))

	listing := run("ls", [f"{SKILL}/references"]).wait()
	if listing.is_error(): return out

	for name in listing.get().stdout.decode_utf8().get_or("").lines():
		if name.is_empty(): continue

		text := read_text(f"{SKILL}/references/{name}")
		if text.is_some(): out.append(
			Page(path: f"references/{name}", text: text.get())
		)

	return out

fn examples(ms: String, page: Page, var count: Int, var issues: List[String]) Int:
	for fence in page.text.split("```manuscript\n").drop(1):
		source := fence.split("```")[0].clone()
		for line in source.lines():
			if line.starts_with(" "): issues.append(
				f"{page.path}: skill code indentation must use tabs"
			)

	for after in page.text.split("<!-- complete").drop(1):
		marker := after.index_of(" -->\n")

		if marker.is_none():
			issues.append(f"{page.path}: complete marker has no end")
			continue

		rest := after.slice(marker.get() + 5, after.length())
		source := fence_after(rest, "```manuscript\n")

		if source.is_none():
			issues.append(
				f"{page.path}: complete marker is not followed by a Manuscript fence"
			)
			continue

		count += 1
		for message in check_messages(ms, "skill_example.ms", source.get()):
			issues.append(f"{page.path}: complete example: {message}")

	return count

// The skill pages' structure and examples.
export fn skill_pages() List[String]:
	ms := tool_ms(".")
	var issues = List[String]()
	create_directory(SCRATCH, recursive: true).get()

	all := pages()
	if all.is_empty(): return [f"cannot read {SKILL}"]

	var count = 0
	for page in all: count = examples(ms, page, count, issues)
	if count != EXAMPLES: issues.append(
		f"skill has {count} complete examples, expected {EXAMPLES}; retain them all"
	)

	root := all[0].text
	if root.length() > 13000: issues.append(
		"SKILL.md should remain concise (13000 bytes)"
	)
	if not root.starts_with("---\nname: manuscript\n"): issues.append(
		"SKILL.md must start with the manuscript front matter"
	)
	if not root.contains("{{MS_VERSION}}"): issues.append(
		"SKILL.md lacks {{MS_VERSION}}"
	)
	if not root.contains("Use tabs for indentation"): issues.append(
		"SKILL.md lacks the tabs rule"
	)

	for page in all.drop(1):
		if not root.contains(page.path): issues.append(
			f"{page.path}: unreachable from SKILL.md"
		)
		if page.text.length() < 600: issues.append(
			f"{page.path}: a reference must teach its concept"
		)
		if not page.text.contains("```manuscript"): issues.append(
			f"{page.path}: a reference needs a real example"
		)

	return issues

// The server-state example is also a conformance fixture, which runs it.
export fn skill_server_state() List[String]:
	page := read_text(f"{SKILL}/references/servers-and-state.md")
	conformance := read_text(
		"tests/conformance/fixtures/e2e/stdlib/serve-state-owner.ms"
	)
	if page.is_none() or conformance.is_none(): return [
		"cannot read the server-state example or its fixture"
	]

	marker := "<!-- complete: server-state.ms -->\n```manuscript\n"
	at := page.get().index_of(marker)
	if at.is_none(): return ["servers-and-state.md lacks the server-state example"]

	rest := page.get().slice(at.get() + marker.length(), page.get().length())
	shown := rest.split("```")[0].clone()
	header := "// conform: tags=testing,tier-io\n// conform: phase=test\n"
	body := conformance.get().cut_prefix(header)
	if body.is_none() or body.get() != shown: return [
		"keep the skill example equal to its fixture"
	]

	return []

// Whether `ms check` read the manifest: it either passes or stops at a later stage that
// the example cannot satisfy alone (a member needs its workspace, a url dependency
// needs
// `ms install`, a workspace root needs member manifests).
fn manifest_accepted(out: CommandOutput) Bool:
	if out.exit_code == 0: return true

	report := out.stderr.decode_utf8().get_or("").concat(
		out.stdout.decode_utf8().get_or("")
	)
	for later in LATER_STAGES:
		if report.contains(later): return true
	return false

// Every `ms.toml` the projects page shows loads with the real manifest reader, so the
// page cannot teach a table or key the compiler rejects.
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run
export fn skill_manifests() List[String]:
	page := read_text(f"{SKILL}/references/projects-and-packages.md")
	if page.is_none(): return ["cannot read the projects page"]

	ms := tool_ms(".")
	var issues = List[String]()
	var parsed = 0

	for after in page.get().split("<!-- manifest: ").drop(1):
		marker := after.index_of(" -->\n")

		if marker.is_none():
			issues.append("manifest marker has no end")
			continue

		name := after.slice(0, marker.get())
		rest := after.slice(marker.get() + 5, after.length())
		text := fence_after(rest, "```toml\n")

		if text.is_none():
			issues.append(f"manifest {name}: no toml fence")
			continue

		dir := f"{SCRATCH}/manifest-{name}"
		remove(dir, recursive: true).get_or(void)
		for sub in ["src/domain", "assets", "app/src", "libs/util/src"]: create_directory(
			f"{dir}/{sub}",
			recursive: true,
		).get()
		for file in ["src/main.ms", "app/src/main.ms", "libs/util/src/greet.ms"]: (
			write_file(f"{dir}/{file}", "fn main() Void:\n\tvoid\n")
			.wait()
			.get()
		)
		write_file(
			f"{dir}/libs/util/ms.toml",
			"[project]\nname = \"util\"\nsource = \"src\"\n",
		).wait().get()
		write_file(
			f"{dir}/src/domain/customers.ms",
			"export type Customer:\n\tid: Int\n",
		).wait().get()

		manifest := if name == "member": f"{dir}/app/ms.toml" else: f"{dir}/ms.toml"
		write_file(manifest, text.get()).wait().get()

		out := run(ms, ["check", manifest]).wait()
		if out.is_error() or not manifest_accepted(out.get()): issues.append(
			f"manifest example {name} is rejected"
		)
		parsed += 1

	if parsed != MANIFESTS: issues.append(
		f"skill has {parsed} manifest examples, expected {MANIFESTS}"
	)
	return issues

// One common mistake: `wrong` and `right` replace `{}` in `body`, inside `main`.
type Mistake:
	wrong: String
	right: String
	setup: String
	body: String
	// A fragment of the diagnostic `wrong` produces, or none when it checks clean.
	diagnostic: String?

fn field(block: List[String], key: String) String?:
	prefix := f"{key}: "
	for line in block:
		if line.starts_with(prefix): return line.slice(prefix.length(), line.length())
	return none

fn mistake_entries(text: String) List[Mistake]:
	var entries = List[Mistake]()

	for chunk in text.split("\n\n"):
		var block = List[String]()
		for line in chunk.lines():
			if not line.starts_with("#"): block.append(line.clone())

		wrong := field(block, "wrong")
		right := field(block, "right")
		if wrong.is_none() or right.is_none(): continue

		diag := field(block, "diag")
		entries.append(
			Mistake(
				wrong: wrong.get(),
				right: right.get(),
				setup: field(block, "setup").get_or(""),
				body: field(block, "body").get_or("{}"),
				diagnostic: if diag.is_some()
				and diag.get() != "-": diag.get() else: none,
			)
		)

	return entries

fn mistake_program(m: Mistake, text: String) String:
	filled := m.body.replace("{}", text).replace(";;", "\n    ")
	setup := m.setup.replace(";;", "\n")
	return f"{setup}\nexport fn main() Int:\n    {filled}\n    return 0\n"

// Every listed mistake is real: `wrong` fails (or is silently accepted) as stated and
// `right` checks clean.
export fn skill_mistakes() List[String]:
	listing := read_text(MISTAKES)
	if listing.is_none(): return [f"cannot read {MISTAKES}"]

	entries := mistake_entries(listing.get())
	var issues = List[String]()
	if entries.length() < 10: issues.append(
		f"mistakes list shrank to {entries.length()}"
	)

	ms := tool_ms(".")
	create_directory(SCRATCH, recursive: true).get()

	for m in entries:
		wrong := check_messages(ms, "mistake.ms", mistake_program(m, m.wrong))

		if fragment := m.diagnostic:
			if not wrong.any(fn message: message.contains(fragment)): issues.append(
				f"mistake `{m.wrong}` should report {fragment}, got {wrong}"
			)
		else if not wrong.is_empty():
			issues.append(f"mistake `{m.wrong}` should check clean: {wrong}")

		right := check_messages(ms, "fixed.ms", mistake_program(m, m.right))
		if not right.is_empty(): issues.append(
			f"mistake fix `{m.right}` should check clean: {right}"
		)

	return issues

test "a fence is read up to its closing fence":
	(
		fence_after("```manuscript\nx := 1\n```\nrest", "```manuscript\n").get()
		| expect_equal(expected: "x := 1\n")?
	)
	fence_after("text", "```manuscript\n").is_none() | expect_equal(expected: true)?
