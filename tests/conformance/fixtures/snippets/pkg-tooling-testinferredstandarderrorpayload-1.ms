# conform: tags=diagnostics,match,modules,stdlib-fs,strings,tier-io
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:143 TestInferredStandardErrorPayload
from "@std/fs.ms" import filesystem

def classify(path: String) -> String:
    match filesystem().stat(path: path, follow_links: True):
        case error(NotFound): return "missing"
        case ok(_): return "exists"
