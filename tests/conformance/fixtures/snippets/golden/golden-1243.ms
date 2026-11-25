// conform: tags=diagnostics
// conform: phase=check
fn work(values List[String]) Void {
    values.append(value: |
}
// expect-error: MS1000 5:1 mismatched closing delimiter '}'; the '(' opened at line 4:18 needs ')'
