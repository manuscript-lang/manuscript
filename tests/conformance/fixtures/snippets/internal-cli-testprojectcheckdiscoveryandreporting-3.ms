# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/project_check_test.go:52 TestProjectCheckDiscoveryAndReporting
from "@lib/value.ms" import value

def report() -> Int: return value()
