# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_test.go:205 TestFormatKeepsConsecutiveConstantsTogether
from "@std/collections.ms" import ListBuilder

let A = 1
let B = 2

def f() -> Int:
    return A + B
