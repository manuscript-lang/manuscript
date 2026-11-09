fn make() List[Int]:
    return [1]

fn go() Unit:
    make()[0] = 1  // error: an assignment target must be a variable
    [1, 2][0] = 3  // error: an assignment target must be a variable
