fn make(n: Int) ref String:  # error: returns `ref`, but no `return` gives back part of a parameter
    return "{n}"
