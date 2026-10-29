# conform: tags=modules,stdlib-testing,testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/library_project_test.go:64 TestLibraryProjectCommandsAndCache
import fail from "@std/test.ms"

export fn other() Int: return 4

test "unimported":
    return fail("changed unimported test")
