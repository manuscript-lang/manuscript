# conform: tags=interpolation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:109 TestInterpolationSpacesAndPhysicalPositions
fn render() String:
    return "hello { @ }"
