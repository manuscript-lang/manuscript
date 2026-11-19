fn replace_key(var key: String) Int:
    key = "long-dynamic-map-key-2"
    return 5

fn add(var value: Int, amount: Int) Void:
    value += amount

fn demo(var values: Map[String, Int], var key: String) Void:
    add(values[key], replace_key(key))  // error: argument `replace_key(..)` of `add` is moved or changed in place but overlaps argument `values[..]`; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
