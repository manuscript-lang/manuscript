// conform: tags=control-flow,diagnostics,interfaces,records,tier-core
// conform: phase=check
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
