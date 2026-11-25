// conform: tags=diagnostics
// conform: phase=check
let (
    A = 1
    B: Int = A + 1
)

fn main() Void {
    var (
        a = 10
        b = fn(x: Int) Int {
            return x + 1
        }
    )
    let (
        c = 11
        d = "Hi"
    )
    a += 1
}
// expect-error: MS1000 3:1-3:4 'let' is not a Manuscript declaration keyword; write 'NAME := value' (or 'NAME: Type := value') for a module constant
// expect-error: MS1000 11:17-11:18 remove the ':' between 'x' and its type; write x Type
// expect-fix: 11:17-11:18 ""
// expect-error: MS1000 13:9 mismatched closing delimiter '}'; the '(' opened at line 9:9 needs ')'
// expect-error: MS1000 16:11-16:12 argument labels use a colon; write c: value
// expect-error: MS1000 17:11-17:12 argument labels use a colon; write d: value
