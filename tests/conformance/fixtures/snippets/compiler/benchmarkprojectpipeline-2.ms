// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/project_bench_test.go:33 BenchmarkProjectPipeline
import value from "./shared.ms"

export fn result() Int => return value()
// expect-error: MS2002 4:1 cannot find module ./shared.ms (looked for shared.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
