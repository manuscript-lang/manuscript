// conform: tags=testing,tier-core
// conform: phase=check
import lines, stdin from "@std/io/io.ms"

export fn main() Int {
	reader := lines(stdin())
	for line in reader {
		if line == "" { return 1 }
	}
	return 0
}
// expect-error: MS2002 3:8-3:13 module does not export lines; another standard module exports it, so replace this import with: import lines from "@std/io/steps.ms"
// expect-error: MS2001 6:15 unknown binding lines; add: import lines from "@std/io/steps.ms"
// expect-fix: 1:1-1:1 "import lines from \"@std/io/steps.ms\"\n"
