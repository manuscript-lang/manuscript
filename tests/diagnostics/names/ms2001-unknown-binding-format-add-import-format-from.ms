// conform: tags=diagnostics
// conform: phase=check
fn work() String {
	values := [1, 2, 3]
	text := f"# A deliberately long literal with {format(value: "nested text")} that must retain its exact original spelling."
	if enabled { return text }

	return text
}
// expect-error: MS2001 5:51 unknown binding format; add: import format from "@std/net/url.ms"
// expect-fix: 1:1-1:1 "import format from \"@std/net/url.ms\"\n"
// expect-error: MS2001 6:8 unknown binding enabled; declare it with 'enabled := ...' before use, define 'fn enabled(...) T { ... }', or import it from a module
