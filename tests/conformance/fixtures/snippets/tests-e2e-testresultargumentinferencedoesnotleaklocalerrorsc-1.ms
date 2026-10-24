# conform: tags=diagnostics,modules,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/result_argument_scope_test.go:13 TestResultArgumentInferenceDoesNotLeakLocalErrorScope
from "./helper.ms" import erase

def invalid(r: Result[Int, Cause[Int]]) -> Result[Int, Error]: erase(r)
