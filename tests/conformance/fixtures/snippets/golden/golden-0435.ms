// conform: tags=diagnostics
// conform: phase=check
value := choose(first: fn() {
        value := checked()?
        return Result[Int, TextError].ok(value)
    , second: () => ok(4))
}
// expect-error: MS1000 6:26 mismatched closing delimiter ')'; the '{' opened at line 3:29 needs '}'
