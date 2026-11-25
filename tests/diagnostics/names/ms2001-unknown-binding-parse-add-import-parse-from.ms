// conform: tags=diagnostics
// conform: phase=check
fn process(input String) Int {
	records := parse(input)
	if records.length() == 0 { return 0 }
	if records.length() > 100 { return 1 }

	report := summarize(records)
	payload := encode(report)

	match save(payload) {
		ok(_) => {
			return 0
		}
		error(_) => {
			return 1
		}
	}
}
// expect-error: MS2001 4:16 unknown binding parse; add: import parse from "@std/data/csv.ms"
// expect-fix: 1:1-1:1 "import parse from \"@std/data/csv.ms\"\n"
// expect-error: MS2001 8:15 unknown binding summarize; declare it with 'summarize := ...' before use, define 'fn summarize(...) T { ... }', or import it from a module
// expect-error: MS2001 9:16 unknown binding encode; declare it with 'encode := ...' before use, define 'fn encode(...) T { ... }', or import it from a module
// expect-error: MS2001 11:11 unknown binding save; declare it with 'save := ...' before use, define 'fn save(...) T { ... }', or import it from a module
