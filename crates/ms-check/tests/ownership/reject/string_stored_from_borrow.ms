type Tag:
    name: String

def first_tag(names: List[String]) -> Tag:
    let w = names.get(0)
    return Tag(name: w)  # error: only borrows its value
