// conform: tags=diagnostics
// conform: phase=check
    let v%d = value.f%d
// expect-error: MS1000 3:10-3:11 expected ':=', found '%'
