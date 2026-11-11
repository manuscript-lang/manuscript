fn grow(value: String!String) String!String:
    output := value?
    return ok(output + "x")

fn keep(value: String!String) Int:
    var kept: List[String!String] = []
    kept.append(grow(value))  // error: `grow` returns a reference into `value`, which this position would keep
    return kept.length()
