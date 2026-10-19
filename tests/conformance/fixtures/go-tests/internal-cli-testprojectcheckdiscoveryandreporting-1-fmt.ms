# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/project_check_test.go:49 TestProjectCheckDiscoveryAndReporting
import value from "./lib/value.ms"
export fn main() Int:
    return value()
