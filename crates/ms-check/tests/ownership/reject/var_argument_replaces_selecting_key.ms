fn replace_key(var key: String) Int:
    key = "long-dynamic-map-key-2"
    return 5

fn add(var value: Int, amount: Int) Unit:
    value += amount

fn demo(var values: Map[String, Int], var key: String) Unit:
    add(var values[key], replace_key(var key))  // error: argument `replace_key(..)` of `add` is changed in place but overlaps argument `values[..]`; a changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
