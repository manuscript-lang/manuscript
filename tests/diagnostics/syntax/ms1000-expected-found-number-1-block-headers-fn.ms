// conform: tags=diagnostics
// conform: phase=check
fn helper() Int 1
let (
    A = 1
    B: Int   = A+1
)
fn main() Void {
    x := 1
    var (
        a = 10
        b = fn(x: Int) Int {
            return x + 1
        }
    )
    let (
        c=11
        d = "Hi"
    )
    a += x + b(c)
}
// expect-error: MS1000 3:17-3:18 expected '{', found number 1; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
// expect-error: MS1000 4:1-4:4 'let' is not a Manuscript declaration keyword; write 'NAME := value' (or 'NAME: Type := value') for a module constant
// expect-error: MS1000 12:17-12:18 remove the ':' between 'x' and its type; write x Type
// expect-fix: 12:17-12:18 ""
// expect-error: MS1000 14:9 mismatched closing delimiter '}'; the '(' opened at line 10:9 needs ')'
// expect-error: MS1000 17:10-17:11 argument labels use a colon; write c: value
// expect-error: MS1000 18:11-18:12 argument labels use a colon; write d: value
