# conform: tags=faults,modules,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=internal/cli/project_check_test.go:53 TestProjectCheckDiscoveryAndReporting
import panic from "@std/faults.ms"
test "never execute":
    return panic("check executed code")
