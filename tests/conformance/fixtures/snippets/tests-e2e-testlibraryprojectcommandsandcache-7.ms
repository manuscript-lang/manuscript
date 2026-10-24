# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=tests/e2e/library_project_test.go:81 TestLibraryProjectCommandsAndCache
from "@lib/value.ms" import value

export def main() -> Int: return value() - 3
