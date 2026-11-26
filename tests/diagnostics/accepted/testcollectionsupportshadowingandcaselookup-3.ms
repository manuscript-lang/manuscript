// conform: tags=alternatives,diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:108 TestCollectionSupportShadowingAndCaseLookup
enum Other {
	OutOfRange
}

fn get() Other => OutOfRange
// expect-exit: 0
