// conform: tags=diagnostics
// conform: phase=check
interface Read {
    fn get() Int
}
fn old(value Read & Equal) Void {
    return
}
// expect-error: MS1000 6:19-6:20 expected ')', found '&'; close the parenthesis, separating items with commas
