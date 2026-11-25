// conform: tags=diagnostics
// conform: phase=check
)
        i += 1
    result := b.freeze()
// expect-error: MS1000 3:1-3:2 unmatched closing delimiter ')'; remove it or add the matching opener before it
