// conform: tags=diagnostics
// conform: phase=check
fn use(entries Map[String, Int]) Void {
    entries.add(key: "a", value: |
}
// expect-error: MS1000 5:1 mismatched closing delimiter '}'; the '(' opened at line 4:16 needs ')'
