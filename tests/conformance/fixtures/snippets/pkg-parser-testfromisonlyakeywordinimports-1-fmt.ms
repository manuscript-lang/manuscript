# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:71 TestFromIsOnlyAKeywordInImports
from "./x.ms" import a

def f(from: Int) -> Int:
    let to = from + 1
    return to
