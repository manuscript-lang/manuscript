// conform: tags=testing,tier-core
// conform: phase=check
type P {
	n Int
}

fn run(f fn(P) Void) Void {
	void f
}

fn changes(var p P) Void {
	p.n = 1
}

test "a function that changes its parameter is not one that only reads it" {
	run(changes)
}
// expect-error: MS3001 16:9 expected fn(P) Void, found fn(var P) Void (in argument 'f' of run)
