# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/project_check_test.go:49 TestProjectCheckDiscoveryAndReporting
from "./lib/value.ms" import value

export def main() -> Int:
    return value()
