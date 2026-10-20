# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/project_check_test.go:52 TestProjectCheckDiscoveryAndReporting
import value from "@lib/value.ms"
fn report() Int: return value()
