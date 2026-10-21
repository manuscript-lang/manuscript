# conform: tags=faults,modules,parser,records,stdlib-faults,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/positional_arguments_test.go:21 TestPositionalArgumentStopsLaterEvaluation
import panic from "@std/core.ms"
fn fail() Int: panic("first supplied argument")
fn later() Int: panic("later argument or default")
fn outer(first: Int, second: Int = later()) Int: panic("outer body")
type Pair:
    first: Int
    second: Int
export fn main() Int:
    let ignored = 
