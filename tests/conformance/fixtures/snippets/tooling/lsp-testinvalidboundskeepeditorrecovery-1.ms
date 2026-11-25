// conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/bound_recovery_test.go:9 TestInvalidBoundsKeepEditorRecovery
interface Named {
	fn name() String
}

type Box[Named Named] {
	cause Named
}

fn Box[Named].name() String => self.cause.name()

type Neighbor {
	value Int
}

fn read(item Neighbor) Int => item.value
// expect-error: MS3000 8:16 a bound must be an interface, but Named resolves to a type parameter; rename the type parameter or name an interface
// expect-error: MS2001 12:43 unknown or ambiguous member name on Named; Named has no bound, so it has no operations: bound it where it is declared, as in `fn f[Named: Contract]` for a function or `fn var Repository[Named: Contract].add` for a method of a generic type
