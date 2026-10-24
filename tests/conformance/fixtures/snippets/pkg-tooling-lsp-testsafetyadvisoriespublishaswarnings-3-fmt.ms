# conform: tags=formatter,match,modules,parser,stdlib-fs,strings,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/advisory_lint_test.go:20 TestSafetyAdvisoriesPublishAsWarnings
# café 🦀
from "@std/fs.ms" import filesystem

def use(path: String) -> Int:
    match filesystem().stat(path: path, follow_links: True):
        case error(NotFound): return 1
        case ok(_): return 0
