// conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/redundant_labels_test.go:11 TestDropRedundantLabels
type Point {
	x Int
	y Int
}

fn bump(map Int, key Int, step Int = 1) Int => map + key + step

type Counter {
	total Int
}

interface Adder {
	fn add(amount Int, extra Int) Int
}

fn Counter.add(amount Int, extra Int) Int => self.total + amount + extra

fn use(map Int, key Int, y Int, x Int, counter Counter) Int { ... }
// expect-format: rewritten
// expect-formatted: type Point {
// expect-formatted: \tx, y Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn bump(map, key Int, step Int = 1) Int => map + key + step
// expect-formatted:
// expect-formatted: type Counter {
// expect-formatted: \ttotal Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: interface Adder {
// expect-formatted: \tfn add(amount, extra Int) Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Counter.add(amount, extra Int) Int => self.total + amount + extra
// expect-formatted:
// expect-formatted: fn use(map, key, y, x Int, counter Counter) Int { ... }
