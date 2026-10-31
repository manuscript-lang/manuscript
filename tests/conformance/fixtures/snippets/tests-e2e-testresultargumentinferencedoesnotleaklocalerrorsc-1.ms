# conform: tags=diagnostics,modules,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/result_argument_scope_test.go:13 TestResultArgumentInferenceDoesNotLeakLocalErrorScope
import erase from "./helper.ms"

fn invalid(r: Result[Int, Cause[Int]]) Int!: erase(r)
