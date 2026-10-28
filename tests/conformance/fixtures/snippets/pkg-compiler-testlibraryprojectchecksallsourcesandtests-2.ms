# conform: tags=diagnostics,modules,testing,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/library_project_test.go:31 TestLibraryProjectChecksAllSourcesAndTests
import value from "@lib/value.ms"

test "value":
    let n = value()
