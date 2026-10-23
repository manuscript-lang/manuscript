# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/format/format_test.go:205 TestFormatKeepsConsecutiveConstantsTogether
import ListBuilder from "@std/collections.ms"

let A = 1
let B = 2

fn f() Int:
    return A + B
