interface Sink:
    fn put(s: String, var into: List[String]) Unit  # error: cannot take a `var` parameter
