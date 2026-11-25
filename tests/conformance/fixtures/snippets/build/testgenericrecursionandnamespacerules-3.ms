// conform: tags=diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:258 TestGenericRecursionAndNamespaceRules
type Box[Int] {
	value Int
}
// expect-error: MS2001 4:10 duplicate or intrinsic type parameter Int; choose a different type parameter name
