// Applies the fix edits of lint findings to source text, the way `ms lint --fix` does:
// equal edits collapse, edits are taken in source order, and an edit that overlaps an
// earlier one or lies outside the text is left for the next run.
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",

	Finding, finding, with_fix from "./finding.ms",
)

// One edit: the bytes `from..to` become `text`.
type Edit:
	from: Int
	to: Int
	text: String

// The text after the edits, and how many were applied.
export type Fixed:
	text: String
	applied: Int

// Whether edit `a` is applied before `b`: by start, then end, then replacement.
fn before(a: Edit, b: Edit) Bool:
	if a.from != b.from: return a.from < b.from
	if a.to != b.to: return a.to < b.to

	return a.text < b.text

fn same(a: Edit, b: Edit) Bool:
	return a.from == b.from and a.to == b.to and a.text == b.text

// The distinct edits the findings carry, in application order.
fn edits_of(findings: List[Finding]) List[Edit]:
	var edits = List[Edit]()

	for item in findings:
		if item.fix_from < 0: continue

		next := Edit(from: item.fix_from, to: item.fix_to, text: item.fix_text.clone())
		var at = edits.length()
		while at > 0 and before(next, edits[at - 1]): at -= 1
		if at > 0 and same(edits[at - 1], next): continue
		if at < edits.length() and same(edits[at], next): continue

		edits.insert(at, next)

	return edits

// `text` with the fixes of `findings` applied.
export fn apply_fixes(text: String, findings: List[Finding]) Fixed:
	source := text.to_bytes()
	var out = "".to_bytes()
	var at = 0
	var applied = 0

	for edit in edits_of(findings):
		if edit.to < edit.from or edit.to > source.length() or edit.from < at: continue

		out = out.concat(source.view(at, edit.from)).concat(edit.text.to_bytes())
		at = edit.to
		applied += 1

	out = out.concat(source.view(at, source.length()))
	return Fixed(text: out.decode_utf8().get_or(text), applied: applied)

test "edits apply in order, once, and overlaps wait":
	base := finding("MSL126", "error", "m", "t.ms", 0, 1, 1)
	found := [
		with_fix(base, 4, 7, "XY"),
		with_fix(base, 0, 2, "A"),
		with_fix(base, 0, 2, "A"),
		with_fix(base, 5, 6, "overlap"),
	]
	fixed := apply_fixes("abcdefghij", found)
	fixed.text | expect_equal(expected: "AcdXYhij")?
	fixed.applied | expect_equal(expected: 2)?
