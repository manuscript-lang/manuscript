// conform: tags=diagnostics
// conform: phase=check
    let map%d = Map[Int, Int]()
    map%d.add(1, 2)
// expect-error: MS1000 3:12-3:13 expected ':=', found '%'
