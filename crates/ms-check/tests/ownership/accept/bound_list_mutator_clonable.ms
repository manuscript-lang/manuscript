fn demo() Int:
    var names = ["a"]
    let set = names.set
    set(0, "b")
    let add = names.append
    add("c")
    var counts = {"a": 1}
    let put = counts.add
    put("b", 2)
    return names.length() + counts.length()
