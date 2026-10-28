def exercise() -> Int:
    let _positional = List[Int](1, reserve: 2)
    let _named_first = List[Int](reserve: 2, 1)
    let _unknown = List[Int](extra: 1, reserve: 2)
    let _duplicate = List[Int](reserve: 1, reserve: 2)
    let _valid = List[Int](reserve: 2)
    return 0
