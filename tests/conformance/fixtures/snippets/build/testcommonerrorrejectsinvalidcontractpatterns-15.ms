// conform: tags=control-flow,diagnostics,generics,interfaces,match,records,strings,tier-core
// conform: phase=check
// conform: origin=pkg/build/library_test.go:150 TestCommonErrorRejectsInvalidContractPatterns
type Box[T] {
	item T
}

interface Named {
	fn name() String
}

fn Box[T].name() String {
	return "box"
}

fn wrong(item Named) String {
	match item {
		Box(value) => {
			return value.name()
		}
		_ => {
			return item.name()
		}
	}
}
// expect-error: MS3000 18:9 concrete type pattern requires explicit type arguments; write e.g. Box[Int]
