// conform: tags=alternatives,diagnostics,formatter,optional,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:16 TestPreludeRetainsCaseInferenceAndLookupRules
enum Other {
	Int
}

fn f() Int? {
	return 1
}
// expect-exit: 0
