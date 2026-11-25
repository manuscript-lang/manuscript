// conform: tags=testing,tier-core
// conform: phase=check
fn missing_context() Void {
	_outcome := error("missing")
}
// expect-error: MS3080 4:17 cannot infer constructor type argument T; write the type arguments, e.g. Box[Int](...), or annotate the binding
