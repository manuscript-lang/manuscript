# conform: tags=formatter,match,modules,parser,stdlib-fs,strings,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/advisory_lint_test.go:20 TestSafetyAdvisoriesPublishAsWarnings
# café 🦀
import stat from "@std/fs.ms"

fn use(path: String) Int:
    match stat(path: path, follow_links: true):
        error(NotFound): return 1
        ok(_): return 0
