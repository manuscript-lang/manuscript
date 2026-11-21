// `ms explain`: the rule family and usual repair of diagnostic codes. The table is
// `data/codes.tsv`, written from the compiler's and the linter's code tables by
// `MS_BLESS=1 cargo test -p ms-cli explain_table`: code, family, severity, repair.
import (
	Matches from "@std/cli/command.ms",
	JsonValue from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",

	list_of, number, object, render_document, text, with from "./json_out.ms",
	files from "@data",
)

type Entry:
	code: String
	family: String
	severity: String
	repair: String

fn entries(table: String) List[Entry]:
	var out = List[Entry]()

	for line in table.split("\n"):
		fields := line.split("\t")
		if fields.length() != 4: continue

		out.append(
			Entry(
				fields[0].clone(),
				fields[1].clone(),
				fields[2].clone(),
				fields[3].clone(),
			)
		)

	return out

// The entry for `code`, matched without regard to case; compiler codes come first.
fn find(known: List[Entry], code: String) Entry?:
	wanted := code.lower()
	for entry in known:
		if entry.code.lower() == wanted: return entry.clone()
	return none

fn plain(entry: Entry) String:
	if entry.severity.is_empty(): return f"{entry.code}: {entry.family}\n  repair: {entry.repair}\n"
	return f"{entry.code}: {entry.family} ({entry.severity})\n  repair: {entry.repair}\n"

fn as_json(entry: Entry) JsonValue:
	var out = object()
	out = with(out, "code", text(entry.code))
	out = with(out, "family", text(entry.family))
	if not entry.severity.is_empty(): out = with(out, "severity", text(entry.severity))
	return with(out, "repair", text(entry.repair))

// What `ms explain` prints for `codes`: standard output, standard error and the status.
export type Explained:
	stdout: String = ""
	stderr: String = ""
	status: Int = 0

export fn explain(table: String, codes: List[String], json: Bool) Explained:
	known := entries(table)
	var out = Explained()
	var found = List[JsonValue]()

	for code in codes:
		entry := find(known, code)

		if not entry.is_some():
			out.stderr += f"ms explain: unknown diagnostic code {code}\n"
			out.status = 1
			continue

		if shown := entry:
			if json:
				found.append(as_json(shown))
			else:
				out.stdout += plain(shown)

	if json:
		var document = object()
		document = with(document, "format", number(1))
		document = with(document, "codes", list_of(found))
		out.stdout = render_document(document)

	return out

// Runs `ms explain` on the codes and `--json` the command tree parsed.
export fn run_explain(m: Matches) Explained:
	codes := m.list("code")
	json := m.bool("json")
	table := files().read("codes.tsv", none).get_or(
		"".to_bytes()
	).decode_utf8().get_or("")
	return explain(table, codes, json)

test "a compiler code prints its family and repair":
	table := "MS1000\tSyntax\t\tfix it\nMSL001\tSpace\twarning\ttrim\n"
	got := explain(table, ["ms1000", "MSL001", "X"], false)
	expect_equal(
		got.stdout,
		"MS1000: Syntax\n  repair: fix it\nMSL001: Space (warning)\n  repair: trim\n",
	)?
	expect_equal(got.stderr, "ms explain: unknown diagnostic code X\n")?
	expect_equal(got.status, 1)?
