// conform: tags=control-flow,diagnostics,formatter,scope-cleanup,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_paragraphs_test.go:83 TestFormatParagraphs
fn work(enabled Bool) Int {
	count := 2

	if enabled {
		run(count)
	} else if count > 0 {
		run(1)
	} else {
		run(0)
	}

	while enabled {
		if count == 0 { break }

		run(count)
		break
	}

	for item in [1, 2] {
		if item == 1 { continue }

		run(item)
	}

	var resource = acquire()
	run(resource)
	resource.close()
	return count
}
// expect-error: MS2001 8:9 unknown binding run; add: import run from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import run from \"@std/os/process.ms\"\n"
// expect-error: MS2001 10:9 unknown binding run; add: import run from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import run from \"@std/os/process.ms\"\n"
// expect-error: MS2001 12:9 unknown binding run; add: import run from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import run from \"@std/os/process.ms\"\n"
// expect-error: MS2001 18:9 unknown binding run; add: import run from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import run from \"@std/os/process.ms\"\n"
// expect-error: MS2001 25:9 unknown binding run; add: import run from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import run from \"@std/os/process.ms\"\n"
// expect-error: MS2001 28:20 unknown binding acquire; declare it with 'acquire := ...' before use, define 'fn acquire(...) T { ... }', or import it from a module
// expect-error: MS2001 29:5 unknown binding run; add: import run from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import run from \"@std/os/process.ms\"\n"
