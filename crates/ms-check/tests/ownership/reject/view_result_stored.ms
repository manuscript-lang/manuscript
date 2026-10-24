def f(line: String) -> List[String]:
    var saved: List[String] = []
    saved.append(line.trim())  # error: borrows its result from `line`
    return saved
