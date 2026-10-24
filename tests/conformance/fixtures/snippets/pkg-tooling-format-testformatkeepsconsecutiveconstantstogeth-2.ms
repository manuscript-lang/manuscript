# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/format/format_test.go:206 TestFormatKeepsConsecutiveConstantsTogether
from "@std/collections.ms" import ListBuilder

let A = 1
let B = 2

def f() -> Int:
    return A + B
