// conform: tags=diagnostics,formatter,generics,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/effects_test.go:100 TestUniversalToStringReadsWithoutInvokingResources
fn text[T](value T) String {
	return value.to_string()
}
// expect-exit: 0
