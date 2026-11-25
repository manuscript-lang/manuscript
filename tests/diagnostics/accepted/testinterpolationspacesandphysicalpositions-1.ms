// conform: tags=diagnostics,formatter,interpolation,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/parser_test.go:95 TestInterpolationSpacesAndPhysicalPositions
fn add(value Int) Int {
	return value
}

fn render() String {
	return f"héllo { add(value: 2) }"
}
// expect-exit: 0
