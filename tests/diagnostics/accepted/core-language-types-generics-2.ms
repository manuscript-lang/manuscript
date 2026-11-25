// conform: tags=control-flow,diagnostics,formatter,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/generics.md:32
type Key {
	id Int
}

fn Key.equals(other Key) Bool {
	return true
}

fn accepts(value Equal) Void {
	return
}

fn use_view() Void {
	accepts(Key(1))
}
// expect-exit: 0
