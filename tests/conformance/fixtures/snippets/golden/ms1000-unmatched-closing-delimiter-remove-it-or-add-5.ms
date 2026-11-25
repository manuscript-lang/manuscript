// conform: tags=diagnostics
// conform: phase=check
) Int {
    invalid := = 1
    return 1
}
// expect-error: MS1000 3:1-3:2 unmatched closing delimiter ')'; remove it or add the matching opener before it
// expect-error: MS1000 6:1-6:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
