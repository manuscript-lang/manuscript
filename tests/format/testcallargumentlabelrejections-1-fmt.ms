// conform: tags=alternatives,closures,control-flow,formatter,generics,interfaces,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/build/compiler_test.go:33 TestCallArgumentLabelRejections
fn one(value Int) Int {
	return value
}

fn two(left Int, right Int) Int {
	return left - right
}

fn zero() Void {
	return
}

fn identity[T](hold value T) &T {
	return value
}

fn apply(transform fn(Int) Int) Int {
	return transform(1)
}

type Box {
	value Int
}

enum Choice {
	Payload(value Int)
}

interface Read {
	fn get() Int
}

fn Box.get() Int {
	return self.value
}
// expect-format: rewritten
// expect-formatted: fn one(value Int) Int {
// expect-formatted: \treturn value
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn two(left, right Int) Int {
// expect-formatted: \treturn left - right
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn zero() Void {
// expect-formatted: \treturn
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn identity[T](hold value T) &T {
// expect-formatted: \treturn value
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn apply(transform fn(Int) Int) Int {
// expect-formatted: \treturn transform(1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Box {
// expect-formatted: \tvalue Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: enum Choice {
// expect-formatted: \tPayload(value Int)
// expect-formatted: }
// expect-formatted:
// expect-formatted: interface Read {
// expect-formatted: \tfn get() Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Box.get() Int {
// expect-formatted: \treturn self.value
// expect-formatted: }
