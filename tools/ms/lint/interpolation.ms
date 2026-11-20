// The rule that reads interpolated text: an integer literal in braces (MSL117).
import (
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Finding, finding from "./finding.ms",
)

// Whether `text` is one or more ASCII digits.
fn is_digits(text: String) Bool:
	if text.is_empty(): return false

	bytes := text.to_bytes()
	for at in 0..bytes.length():
		if bytes[at] < 48 or bytes[at] > 57: return false
	return true

// `f"\d{4}"` reads as a regex quantifier but interpolates the number 4.
fn number_in_braces(
	tree: Syntax,
	file: String,
	text_kind: Int,
	number: Int,
	var out: List[Finding],
) Void:
	for at in 0..tree.kind.length():
		if tree.kind[at] != text_kind: continue

		for part in children(tree, at):
			if tree.flags[part] % 2 == 0: continue

			inner := children(tree, part)[0]
			if tree.kind[inner] != number: continue

			digits := tree.names[tree.a[inner]].clone()
			if not is_digits(digits): continue

			out.append(
				finding(
					"MSL117",
					"warning",
					f"`\{{digits}\}` interpolates the number {digits}, not a literal brace; write `\\\{{digits}\\\}` for braces (a regex quantifier), or use `r\"...\"` raw text",
					file,
					tree.offset[inner],
					tree.line[inner],
					tree.column[inner],
				)
			)

// The findings for the interpolated text of the module in `text`; none when it does not
// parse.
export fn lint_interpolation(file: String, text: String) List[Finding]:
	var out = List[Finding]()
	parsed := parse(text)
	if parsed.is_error(): return out

	number_in_braces(parsed.get(), file, node_kind("Text"), node_kind("Number"), out)
	return out

test "a number in braces is a quantifier written wrong":
	found := lint_interpolation("t.ms", "x := f\"\\\\d{4}\"\ny := f\"{x}\"\n")
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL117")?
	found[0].line | expect_equal(expected: 1)?
