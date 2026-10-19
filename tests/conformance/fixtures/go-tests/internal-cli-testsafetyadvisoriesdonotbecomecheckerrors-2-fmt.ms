# conform: tags=formatter,match,modules,parser,stdlib-fs,strings,tier-io
# conform: phase=parse
# conform: origin=internal/cli/advisory_lint_test.go:17 TestSafetyAdvisoriesDoNotBecomeCheckErrors
import filesystem from "@std/fs.ms"
fn use(path: String) Int:
    match filesystem().stat(path: path, follow_links: true):
        error(NotFound): return 1
        ok(_): return 0
