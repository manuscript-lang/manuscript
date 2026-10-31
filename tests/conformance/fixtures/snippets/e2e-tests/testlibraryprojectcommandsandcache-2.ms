# conform: tags=control-flow,modules,stdlib-testing,testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/library_project_test.go:30 TestLibraryProjectCommandsAndCache
import fail from "@std/test.ms"

export fn other() Int: return 4

test "unimported":
    if other() != 4: return fail("bad other")
