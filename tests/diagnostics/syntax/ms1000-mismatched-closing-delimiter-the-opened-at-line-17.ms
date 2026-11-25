// conform: tags=diagnostics
// conform: phase=check
fn add(a Int, b Int) Int {
    return a + b
}

export fn main() Int {
    label := "héllo 😀"
    s := add(a: 1, b: 2)
    q := (
    return s
}
// expect-error: MS1000 12:1 mismatched closing delimiter '}'; the '(' opened at line 10:10 needs ')'
