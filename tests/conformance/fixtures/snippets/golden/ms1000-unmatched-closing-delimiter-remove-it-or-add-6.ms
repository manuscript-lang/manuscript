// conform: tags=diagnostics
// conform: phase=check
) Void {
    bound := receiver.
}
// expect-error: MS1000 3:1-3:2 unmatched closing delimiter ')'; remove it or add the matching opener before it
// expect-error: MS1000 5:1-5:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
