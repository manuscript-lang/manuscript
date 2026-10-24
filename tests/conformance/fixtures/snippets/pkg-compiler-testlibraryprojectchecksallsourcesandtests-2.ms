# conform: tags=diagnostics,modules,testing,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/library_project_test.go:31 TestLibraryProjectChecksAllSourcesAndTests
from "@lib/value.ms" import value

test "value":
    let n = value()
