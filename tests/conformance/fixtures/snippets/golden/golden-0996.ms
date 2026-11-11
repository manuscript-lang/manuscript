// conform: tags=diagnostics
// conform: phase=check
fn run() Int:
    return select[Int](
        1,
        last: 3,
        fn value: value + 1,
    )
