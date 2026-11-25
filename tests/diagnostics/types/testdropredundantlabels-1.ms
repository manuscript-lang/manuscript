// conform: tags=control-flow,diagnostics,interfaces,records,tier-core
// conform: phase=check
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
// expect-error: MS3000 21:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
