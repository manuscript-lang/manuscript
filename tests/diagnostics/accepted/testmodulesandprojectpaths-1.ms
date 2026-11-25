// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:238 TestModulesAndProjectPaths
export type Identity {
	value Int
}

export fn read(value Identity) Int {
	return value.value
}
// expect-exit: 0
