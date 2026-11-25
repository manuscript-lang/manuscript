// conform: tags=closures,diagnostics,formatter,generics,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/callback_work_test.go:93 TestCallbackProbeRetainsCapturedBindingsAndOptionalMetadata
fn wrap[T](callback (fn(Int) T)?) Void => return

fn apply[T, U](value T, transform fn(T) U) U => transform(value)

fn first() Void {
	offset := 7
	_result := apply(
		value: 1,
		transform: outer => apply(
			value: 2,
			transform: inner => (outer + inner + offset),
		),
	)
	wrap(fn(item Int = 4) => item + offset)
}
// expect-exit: 0
