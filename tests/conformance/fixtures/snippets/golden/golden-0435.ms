// conform: tags=diagnostics
// conform: phase=check
value := choose(first: fn():
        value := checked()?
        return Result[Int, TextError].ok(value)
    , second: fn(): ok(4))