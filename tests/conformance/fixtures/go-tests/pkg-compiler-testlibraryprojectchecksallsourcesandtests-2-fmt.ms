# conform: tags=formatter,modules,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/library_project_test.go:31 TestLibraryProjectChecksAllSourcesAndTests
import value from "@lib/value.ms"
test "value":
    let n = value()
