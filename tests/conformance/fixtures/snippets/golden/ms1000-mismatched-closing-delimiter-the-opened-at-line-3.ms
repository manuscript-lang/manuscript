// conform: tags=diagnostics
// conform: phase=check
value := choose(first: fn() {
        if true { return null }
        return 1
    , second: () => 2)
}
// expect-error: MS1000 6:22 mismatched closing delimiter ')'; the '{' opened at line 3:29 needs '}'
