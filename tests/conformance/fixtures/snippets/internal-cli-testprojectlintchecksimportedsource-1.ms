# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/cli_test.go:232 TestProjectLintChecksImportedSource
from "./other.ms" import value

def read() -> Int:
    return value()
