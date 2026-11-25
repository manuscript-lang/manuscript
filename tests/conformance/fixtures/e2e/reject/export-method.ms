// conform: tags=modules,diagnostics,tier-core
// conform: phase=check
export type Item {
	n Int
}

export fn Item.show() Int {
	return self.n
}
// expect-error: MS1000 7:1-7:7 only types, enums, interfaces, and named functions can be exported; remove 'export' before this method, test, or bench (a method is exported with its type)
