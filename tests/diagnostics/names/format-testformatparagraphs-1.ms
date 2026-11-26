// conform: tags=control-flow,diagnostics,formatter,scope-cleanup,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_paragraphs_test.go:16 TestFormatParagraphs
fn work(enabled Bool) Int {
	count := 2
	if enabled {
		run(count)
	}
	for item in [1, 2] {
		run(item)
	}

	var resource = acquire()
	run(resource)
	resource.close()
	return count
}
// expect-error: MS2001 7:9 unknown binding run; add: import run from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import run from \"@std/os/process.ms\"\n"
// expect-error: MS2001 10:9 unknown binding run; add: import run from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import run from \"@std/os/process.ms\"\n"
// expect-error: MS2001 13:20 unknown binding acquire; declare it with 'acquire := ...' before use, define 'fn acquire(...) T { ... }', or import it from a module
// expect-error: MS2001 14:5 unknown binding run; add: import run from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import run from \"@std/os/process.ms\"\n"
