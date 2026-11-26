// conform: tags=control-flow,formatter,interfaces,lists,modules,mutation,parser,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/interface-method-calls-cache-each-receiver-type.ms
import expect_true from "@std/test/test.ms"

interface Shape {
	fn area(scale Int) Int
}

type Sq {
	side Int
}

type Rect {
	w Int
	h Int
}

type Tri {
	b Int
	h Int
}

fn Sq.area(scale Int) Int => self.side * self.side * scale

fn Rect.area(scale Int) Int => self.w * self.h * scale

fn Tri.area(scale Int) Int => self.b * self.h * scale / 2

fn measure(shape Shape, scale Int) Int => shape.area(scale: scale)

test "three receiver types alternate at one site" {
	shapes List[Shape] := [Sq(side: 3), Rect(w: 2, h: 5), Tri(b: 4, h: 5)]
	var total = 0
	var round = 0

	while round < 4 {
		var i = 0

		while i < 3 {
			total += measure(shape: shapes[i], scale: 2)
			i += 1
		}

		round += 1
	}

	expect_true((total == 4 * (18 + 20 + 20)))?
}
// expect-format: rewritten
// expect-formatted: import expect_true from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: interface Shape {
// expect-formatted: \tfn area(scale Int) Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Sq {
// expect-formatted: \tside Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Rect {
// expect-formatted: \tw, h Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Tri {
// expect-formatted: \tb, h Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Sq.area(scale Int) Int => self.side * self.side * scale
// expect-formatted:
// expect-formatted: fn Rect.area(scale Int) Int => self.w * self.h * scale
// expect-formatted:
// expect-formatted: fn Tri.area(scale Int) Int => self.b * self.h * scale / 2
// expect-formatted:
// expect-formatted: fn measure(shape Shape, scale Int) Int => shape.area(scale: scale)
// expect-formatted:
// expect-formatted: test "three receiver types alternate at one site" {
// expect-formatted: \tshapes List[Shape] := [Sq(side: 3), Rect(w: 2, h: 5), Tri(b: 4, h: 5)]
// expect-formatted: \tvar total = 0
// expect-formatted: \tvar round = 0
// expect-formatted:
// expect-formatted: \twhile round < 4 {
// expect-formatted: \t\tvar i = 0
// expect-formatted:
// expect-formatted: \t\twhile i < 3 {
// expect-formatted: \t\t\ttotal += measure(shape: shapes[i], scale: 2)
// expect-formatted: \t\t\ti += 1
// expect-formatted: \t\t}
// expect-formatted:
// expect-formatted: \t\tround += 1
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \texpect_true((total == 4 * (18 + 20 + 20)))?
// expect-formatted: }
