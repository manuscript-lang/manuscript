// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=type-aliases
type Row {
	id Int
}

export type Rows = List[Row]
// expect-error: MS3000 8:8 public signature exposes private type Row; add 'export' to its declaration or keep the function private
