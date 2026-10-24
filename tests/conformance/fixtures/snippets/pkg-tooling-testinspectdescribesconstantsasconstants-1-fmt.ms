# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/inspect_constants_test.go:10 TestInspectDescribesConstantsAsConstants
let LIMIT = 10

def size() -> Int:
    return LIMIT
