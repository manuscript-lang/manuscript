ITEMS := [1, 2]

fn total() Int:
    var copy = ITEMS.clone()
    copy.append(3)
    return copy.length() + ITEMS.length()
