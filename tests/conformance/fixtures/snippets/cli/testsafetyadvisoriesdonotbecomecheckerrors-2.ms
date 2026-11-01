# conform: tags=diagnostics,match,modules,stdlib-fs,strings,tier-io
# conform: phase=check
# conform: origin=internal/cli/advisory_lint_test.go:17 TestSafetyAdvisoriesDoNotBecomeCheckErrors
import stat from "@std/os/fs.ms"

fn use(path: String) Int:
    match stat(path: path, follow_links: true):
        error(NotFound): return 1
        ok(_): return 0
