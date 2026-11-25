// conform: tags=diagnostics
// conform: phase=check
// File introduction.
fn example() Int {
	first := 1

	// A deliberate new step.
	second := first + 1
	if second > 2 {
		run(second)
		// A comment inside the branch.
	}

	// A comment on the next step.
	return second
}
// expect-error: MS2001 10:9 unknown binding run; add: import run from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import run from \"@std/os/process.ms\"\n"
