# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/parser/hints_test.go:71 TestFromIsOnlyAKeywordInImports
import {a} from "./x.ms"

fn f(from: Int) Int:
    let to = from + 1
    return to
