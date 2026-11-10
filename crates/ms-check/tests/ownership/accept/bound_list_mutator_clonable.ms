fn demo() Int:
    var names = ["a"]
    set := names.set
    set(0, "b")
    add := names.append
    add("c")
    var counts = {"a": 1}
    put := counts.add
    put("b", 2)
    return names.length() + counts.length()
