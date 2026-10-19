# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/project_bench_test.go:33 BenchmarkProjectPipeline
import value from "./shared.ms"
export fn result() Int: return value()
