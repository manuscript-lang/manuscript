fn exercise() Int:
    _set_named := Set[Int, String](values: [1])
    _set_positional := Set[Int, String]([1])
    _set_unknown := Set[Int, String](extra: [1])
    _set_duplicate := Set[Int, String](values: [1], values: [2])
    _list_named := List[Int, String](reserve: 2)
    _list_mixed := List[Int, String](1, reserve: 2)
    return 0
