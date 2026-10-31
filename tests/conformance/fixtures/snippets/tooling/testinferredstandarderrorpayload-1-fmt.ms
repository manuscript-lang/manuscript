# conform: tags=formatter,match,modules,parser,stdlib-fs,strings,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:143 TestInferredStandardErrorPayload
import stat from "@std/fs.ms"

fn classify(path: String) String:
    match stat(path: path, follow_links: true):
        error(NotFound): return "missing"
        ok(_): return "exists"
