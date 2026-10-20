# conform: tags=modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/pipeline_test.go:71 TestRecoveredSourceRetainsResolutionAndParseDiagnostics
import value from "./local.ms"
fn helper() Int: return 3
fn broken(
