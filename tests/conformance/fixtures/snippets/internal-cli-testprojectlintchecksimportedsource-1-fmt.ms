# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/cli_test.go:232 TestProjectLintChecksImportedSource
from "./other.ms" import value

def read() -> Int:
    return value()
