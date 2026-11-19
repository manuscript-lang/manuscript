fn replace_key(var key: String) Int:
    key = "long-dynamic-map-key-2"
    return 5

fn bump(var index: Int) Int:
    index += 1
    return 5

fn add(var value: Int, amount: Int) Void:
    value += amount

fn demo(var values: Map[String, Int], var counts: List[Int], var key: String, var i: Int) Void:
    add(values[key.clone()], replace_key(key))
    add(counts[i], bump(i))
