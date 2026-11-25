// conform: tags=modules,diagnostics,tier-core
// conform: phase=check
export type Item {
	n Int
}

export fn Item.show() Int {
	return self.n
}
