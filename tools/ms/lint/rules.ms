// Every lint rule ported to Manuscript, run over one module's text.
import (
	Finding from "./finding.ms",
	lint_flow from "./flow.ms",
	lint_imports from "./imports.ms",
	lint_interpolation from "./interpolation.ms",
	lint_matches from "./matches.ms",
	lint_recursion from "./recursion.ms",
	lint_terse from "./terse.ms",
	lint_source from "./text.ms",
)

// The findings of every rule for the module in `text`.
export fn lint_all(file: String, text: String) List[Finding]:
	var found = lint_source(file, text)
	found.extend(lint_matches(file, text))
	found.extend(lint_terse(file, text))
	found.extend(lint_flow(file, text))
	found.extend(lint_imports(file, text))
	found.extend(lint_recursion(file, text))
	found.extend(lint_interpolation(file, text))
	return found
