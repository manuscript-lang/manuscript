// conform: tags=diagnostics
// conform: phase=check
fn work(early: Int) Int:
    result := subtract(
        try match 0:
            _value:
                10
            none: 10
    )
    return result
