def make(n: Int) -> Int:
    let ref s = f"{n}"  # error: borrows part of a value
    return s.length()
