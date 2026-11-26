// conform: tags=diagnostics,formatter,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:259 TestGenericRecursionAndNamespaceRules
type Int {
	value String
}
// expect-error: MS2001 4:1 duplicate or intrinsic name Int; this name is already declared, imported, or built in, so rename one of them
