# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/pipeline_test.go:58 TestSourceAndFileUseTheSamePipeline
export fn main() Int:
    if not false: return 3
    return 0
