// conform: tags=control-flow,diagnostics,formatter,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/named-types.md:52
interface Counter {
	var fn increment() Void
}

type Val {
	val Int
}

fn var Val.increment() Void {
	self.val += 1
}
// expect-exit: 0
