type Tag:
    name: String

def first_tag(names: List[String]) -> Tag:
    let w = names.get(0)
    return Tag(name: w.clone())

def count(words: List[String]) -> Map[String, Int]:
    var m = Map[String, Int]()
    for w in words:
        m.add(w.clone(), 1)
    return m

def length_of(s: String) -> Int:
    return s.length()

def read_twice(s: String) -> Int:
    return length_of(s) + length_of(s)
