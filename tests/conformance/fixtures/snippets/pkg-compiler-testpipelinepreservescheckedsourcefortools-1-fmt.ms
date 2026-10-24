# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/pipeline_test.go:16 TestPipelinePreservesCheckedSourceForTools
def value(flag: Bool = not False) -> Bool:
    let callback = lambda () -> Bool: return not (False or False)
    return (not False and callback()) or flag
