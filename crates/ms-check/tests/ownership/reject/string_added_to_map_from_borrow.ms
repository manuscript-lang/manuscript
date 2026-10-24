def count(words: List[String]) -> Int:
    var m = Map[String, Int]()
    for w in words:
        m.add(w, 1)  # error: only borrows its value
    return m.length() + words.length()
