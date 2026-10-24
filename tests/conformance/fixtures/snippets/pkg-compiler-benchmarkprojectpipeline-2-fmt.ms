# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/project_bench_test.go:33 BenchmarkProjectPipeline
from "./shared.ms" import value

export def result() -> Int: return value()
