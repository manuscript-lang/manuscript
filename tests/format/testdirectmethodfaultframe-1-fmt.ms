// conform: tags=control-flow,formatter,interfaces,parser,records,testing,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/direct_methods_test.go:13 TestDirectMethodFaultFrame
interface Shape {
	fn area() Int
}

type Rect {
	w Int
	h Int
}

fn Rect.area() Int {
	return self.w * self.h
}

test "method fault frame" {
	rect := Rect(w: 9223372036854775807, h: 2)
	rect.area()
}
// expect-format: rewritten
// expect-formatted: interface Shape {
// expect-formatted: \tfn area() Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Rect {
// expect-formatted: \tw, h Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Rect.area() Int {
// expect-formatted: \treturn self.w * self.h
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "method fault frame" {
// expect-formatted: \trect := Rect(w: 9223372036854775807, h: 2)
// expect-formatted: \trect.area()
// expect-formatted: }
