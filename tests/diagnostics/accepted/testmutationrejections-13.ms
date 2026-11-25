// conform: tags=aliasing,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:34 TestMutationRejections
fn f() Void {
	stdout().clone()
}
// expect-error: MS2001 5:5 unknown binding stdout; add: import stdout from "@std/io/io.ms"
// expect-fix: 1:1-1:1 "import stdout from \"@std/io/io.ms\"\n"
