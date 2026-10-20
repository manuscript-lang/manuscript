# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/project_bench_test.go:33 BenchmarkProjectPipeline
import value from "./shared.ms"
export fn result() Int: return value()
