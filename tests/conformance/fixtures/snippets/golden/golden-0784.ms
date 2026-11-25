// conform: tags=diagnostics
// conform: phase=check
fn value() Int {
    return 03
}
// expect-error: MS1001 4:13 leading zeros are not allowed in numeric literals; write the number without them, e.g. 42 instead of 042
