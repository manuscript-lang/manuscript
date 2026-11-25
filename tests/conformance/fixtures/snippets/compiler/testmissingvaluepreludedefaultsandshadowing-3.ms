// conform: tags=alternatives,diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:203 TestMissingValuePreludeDefaultsAndShadowing
enum Other {
	Missing(value Int)
}

fn get() Other => Missing(1)
// expect-exit: 0
