type Tag:
    name: String

fn first_tag(names: List[String]) Tag:
    let w = names.get(0)
    return Tag(name: w.clone())

fn count(words: List[String]) Map[String, Int]:
    var m = Map[String, Int]()
    for w in words:
        m.add(w.clone(), 1)
    return m

fn length_of(s: String) Int:
    return s.length()

fn read_twice(s: String) Int:
    return length_of(s) + length_of(s)
