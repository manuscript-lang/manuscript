# conform: tags=diagnostics,match,modules,stdlib-fs,strings,tier-io
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:143 TestInferredStandardErrorPayload
import filesystem from "@std/fs.ms"
fn classify(path: String) String:
    match filesystem().stat(path: path, follow_links: true):
        error(NotFound): return "missing"
        ok(_): return "exists"
