# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/cli_test.go:232 TestProjectLintChecksImportedSource
import value from "./other.ms"
fn read() Int:
    return value()
