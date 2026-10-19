# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/project_check_test.go:49 TestProjectCheckDiscoveryAndReporting
import value from "./lib/value.ms"
export fn main() Int:
    return value()
