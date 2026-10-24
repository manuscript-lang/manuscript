# conform: tags=diagnostics,match,modules,stdlib-fs,strings,tier-io
# conform: phase=check
# conform: origin=internal/cli/advisory_lint_test.go:17 TestSafetyAdvisoriesDoNotBecomeCheckErrors
from "@std/fs.ms" import filesystem

def use(path: String) -> Int:
    match filesystem().stat(path: path, follow_links: True):
        case error(NotFound): return 1
        case ok(_): return 0
