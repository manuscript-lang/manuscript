// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:79 TestCollectionPreludeAndShadowing
fn f() Void {
	values := Set()
}
// expect-error: MS3080 5:15 cannot infer constructor type argument T; write the type arguments, e.g. Box[Int](...), or annotate the binding
