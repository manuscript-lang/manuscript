# conform: tags=diagnostics,interpolation,strings,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:95 TestInterpolationSpacesAndPhysicalPositions
fn add(value: Int) Int:
    return value
fn render() String:
    return "héllo { add(value: 2) }"
