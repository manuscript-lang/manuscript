// conform: tags=diagnostics,formatter,match,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lint_program_test.go:110 TestMatchArmPayloadBindingsAreLinted
fn answer() Int {
	match parse("1") {
		ok(value) => return value
		error(_) => return 2
	}
}
// expect-error: MS2001 5:11 unknown binding parse; add: import parse from "@std/data/csv.ms"
// expect-fix: 1:1-1:1 "import parse from \"@std/data/csv.ms\"\n"
