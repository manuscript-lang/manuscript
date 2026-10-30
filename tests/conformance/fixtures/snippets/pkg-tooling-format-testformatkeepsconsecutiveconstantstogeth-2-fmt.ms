# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_test.go:206 TestFormatKeepsConsecutiveConstantsTogether
import ListEntry from "@std/collections.ms"

let A = 1
let B = 2

fn f() Int:
    return A + B
