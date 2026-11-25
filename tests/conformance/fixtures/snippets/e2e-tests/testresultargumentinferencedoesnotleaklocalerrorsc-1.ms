// conform: tags=diagnostics,modules,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/result_argument_scope_test.go:13 TestResultArgumentInferenceDoesNotLeakLocalErrorScope
import erase from "./helper.ms"

fn invalid(r Result[Int, Cause[Int]]) Int! => erase(r)
// expect-error: MS2002 4:1 cannot find module ./helper.ms (looked for helper.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
