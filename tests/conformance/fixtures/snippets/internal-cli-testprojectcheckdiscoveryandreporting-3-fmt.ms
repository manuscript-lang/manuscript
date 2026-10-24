# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/project_check_test.go:52 TestProjectCheckDiscoveryAndReporting
from "@lib/value.ms" import value

def report() -> Int: return value()
