# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/project_bench_test.go:33 BenchmarkProjectPipeline
from "./shared.ms" import value

export def result() -> Int: return value()
