# conform: tags=control-flow,tier-core
# conform: phase=run
# conform: origin=pkg/compiler/pipeline_test.go:58 TestSourceAndFileUseTheSamePipeline
export fn main() Int:
    if not false: return 3
    return 0
