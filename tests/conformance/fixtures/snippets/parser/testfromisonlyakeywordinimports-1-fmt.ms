# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:71 TestFromIsOnlyAKeywordInImports
import a from "./x.ms"

fn f(from: Int) Int:
    let to = from + 1
    return to
