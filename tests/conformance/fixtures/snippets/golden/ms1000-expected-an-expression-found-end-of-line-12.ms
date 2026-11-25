// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"
fn fail() Int => panic("first supplied argument")
fn later() Int => panic("later argument or default")
fn outer(first Int, second Int = later()) Int => panic("outer body")
type Pair {
    first Int
    second Int
}
export fn main() Int {
    ignored := 
}
// expect-error: MS1000 12:16-12:16 expected an expression, found end of line; write a value, name, call, or literal here
