# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=tests/e2e/library_project_test.go:81 TestLibraryProjectCommandsAndCache
import value from "@lib/value.ms"

export fn main() Int: return value() - 3
