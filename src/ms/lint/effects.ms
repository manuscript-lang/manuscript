// A function reaches an effect no `// ms: allow_effect` line permits (MSL116). The
// checker follows the references from each function to the ones that declare an effect
// and reports the first reference that brings it in, so this rule only turns what it
// found into findings. A function the scan cannot see through yields none: a violation
// is reported when it is seen, and a missing one proves nothing.
import (
	expect_equal from "@std/test/test.ms",

	analyze from "./analysis.ms",
	Finding, finding from "./finding.ms",
)

// The findings of the effect rule for the module in `source`.
export fn lint_effects(file: String, source: String) List[Finding]:
	var out = List[Finding]()
	facts := analyze(source)
	if facts.is_none(): return out

	for reach in facts.get().effects:
		out.append(
			finding(
				"MSL116",
				"warning",
				reach.message,
				file,
				reach.offset,
				reach.line,
				reach.column,
			)
		)
	return out

test "a function that reaches stdout without permission is reported":
	source := "import stdout from \"@std/io/io.ms\"\n\nfn total() Void:\n    var out = stdout()\n    void out.write(\"x\")\n"
	found := lint_effects("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL116")?
