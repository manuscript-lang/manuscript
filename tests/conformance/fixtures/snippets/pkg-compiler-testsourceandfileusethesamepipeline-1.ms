# conform: tags=control-flow,tier-core
# conform: phase=run
# conform: origin=pkg/compiler/pipeline_test.go:58 TestSourceAndFileUseTheSamePipeline
export def main() -> Int:
    if not False: return 3

    return 0
