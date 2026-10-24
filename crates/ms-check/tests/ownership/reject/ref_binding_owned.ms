fn make(n: Int) Int:
    let ref s = "{n}"  # error: borrows part of a value
    return s.length()
