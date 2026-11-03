fn count(words: List[String]) Int:
    var m = Map[String, Int]()
    for w in words:
        m.add(w, 1)  // error: is borrowed, not owned
    return m.length() + words.length()
