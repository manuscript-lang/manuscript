# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/pipeline_test.go:58 TestSourceAndFileUseTheSamePipeline
export def main() -> Int:
    if not False: return 3

    return 0
