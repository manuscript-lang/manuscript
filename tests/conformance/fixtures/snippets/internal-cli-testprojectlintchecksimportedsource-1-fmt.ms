# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/cli_test.go:232 TestProjectLintChecksImportedSource
import value from "./other.ms"
fn read() Int:
    return value()
