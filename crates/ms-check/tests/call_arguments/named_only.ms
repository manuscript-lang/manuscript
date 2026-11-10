fn exercise() Int:
    _positional := List[Int](1, reserve: 2)
    _named_first := List[Int](reserve: 2, 1)
    _unknown := List[Int](extra: 1, reserve: 2)
    _duplicate := List[Int](reserve: 1, reserve: 2)
    _valid := List[Int](reserve: 2)
    return 0
