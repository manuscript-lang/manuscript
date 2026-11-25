// conform: tags=diagnostics,formatter,match,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/library_test.go:111 TestCommonErrorRejectsInvalidContractPatterns
interface Named {
	fn name() String
}

fn wrong(item Named) String {
	match item {
		Circle.Big(value) => {
			return "invalid"
		}
		_ => {
			return item.name()
		}
	}
}
// expect-error: MS3000 10:9 contract pattern requires a concrete type or enum; name an implementing type like Circle, or use '_'
