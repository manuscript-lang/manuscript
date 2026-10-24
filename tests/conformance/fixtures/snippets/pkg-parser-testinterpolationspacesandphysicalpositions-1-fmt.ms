# conform: tags=formatter,interpolation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:95 TestInterpolationSpacesAndPhysicalPositions
def add(value: Int) -> Int:
    return value

def render() -> String:
    return f"héllo { add(value: 2) }"
