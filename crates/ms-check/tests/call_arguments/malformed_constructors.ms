fn exercise() Int:
    let _set_named = Set[Int, String](values: [1])
    let _set_positional = Set[Int, String]([1])
    let _set_unknown = Set[Int, String](extra: [1])
    let _set_duplicate = Set[Int, String](values: [1], values: [2])
    let _list_named = List[Int, String](reserve: 2)
    let _list_mixed = List[Int, String](1, reserve: 2)
    return 0
