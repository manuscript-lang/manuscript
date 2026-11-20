// Release pins: the editor extension's version, the calendar version and the CI
// triggers.
import (
	parse from "@std/data/json.ms",

	read_text from "./util.ms",
)

export fn extension_version() List[String]:
	release := read_text(".msversion").get_or("")
	manifest := read_text("extensions/vscode/package.json").get_or("")
	if release.is_empty() or manifest.is_empty():
		return ["cannot read .msversion or extensions/vscode/package.json"]

	var version = ""
	if doc := parse(manifest):
		if value := doc.get("version"): version = value.as_string().get_or("")
	if version == release.trim(): return []

	return [
		f"extensions/vscode/package.json version {version} disagrees with .msversion"
	]

fn plain_number(part: String) Bool:
	if part.is_empty(): return false

	for byte in part.as_bytes().values():
		if byte < 48 or byte > 57: return false
	return part == "0" or not part.starts_with("0")

// Why `version` is not `YYYY.M.PATCH`, or "".
export fn calendar_error(version: String) String:
	parts := version.split(".")
	if parts.length() != 3: return "write YYYY.M.PATCH, for example 2026.11.0"
	if not (
		plain_number(parts[0])
		and plain_number(parts[1])
		and plain_number(parts[2])
	):
		return "each part is digits with no leading zero, so the version is valid semver"

	year := parts[0].parse_int().get_or(0)
	month := parts[1].parse_int().get_or(0)
	if year >= 2000 and year <= 9999 and month >= 1 and month <= 12: return ""

	return "the year has four digits and the month is 1 to 12"

export fn calendar_version() List[String]:
	text := read_text(".msversion").get_or("")
	if text.is_empty(): return ["cannot read .msversion"]

	why := calendar_error(text.trim())
	if why.is_empty(): return []

	return [f".msversion \"{text.trim()}\": {why}"]

fn indent_of(line: String) Int: line.length() - line.trim_start().length()

// The lines under `key:` at `indent`, until a line that is not nested deeper; none when
// absent.
fn block(lines: List[String], key: String, indent: Int) List[String]?:
	head := " ".repeat(indent) + key + ":"

	for at in 0..lines.length():
		line := lines[at]

		if line.trim_end() == head or line.starts_with(head + " "):
			var out = List[String]()

			for rest in lines.slice(at + 1, lines.length()).get_or([]):
				if not rest.trim().is_empty() and indent_of(rest) <= indent: break

				out.append(rest.clone())

			return out

	return none

// Why the CI triggers break the rule, or "".
export fn triggers(text: String) String:
	lines := text.lines()
	on := block(lines, "on", 0).get_or([])
	var filtered = true

	if pull := block(on, "pull_request", 2):
		filtered = false
		for line in pull:
			if line.trim_start().starts_with("paths"): filtered = true

	if filtered: return "required checks must run on every pull request without path filters"

	queue := block(on, "merge_group", 2).get_or([])
	var types = List[String]()

	for raw in queue:
		line := raw.trim()
		if line.starts_with("types:") or line.starts_with("- "):
			types.append(line.cut_prefix("types:").get_or(line).trim())

	if not (types == ["[checks_requested]"] or types == ["- checks_requested"]):
		return "required checks must run on merge_group checks_requested"

	return ""

export fn workflow_triggers() List[String]:
	path := ".github/workflows/cicd.yml"
	text := read_text(path).get_or("")
	if text.is_empty(): return [f"{path}: cannot read"]

	why := triggers(text)
	if why.is_empty(): return []

	return [f"{path}: {why}"]
