// expect-mir: "msrt_map_slot_lent"
// expect-mir: "msrt_map_add_lent"
// expect-mir: "msrt_map_add_default_lent"

export fn main() Int:
    let key = "long-dynamic-map-key-{1}"
    var values: Map[String, Int] = Map()
    values.add_default(key.clone(), 0)
    values.add(key.clone(), 0)
    values.update(key.clone(), 0, fn n: n + 1)
    return values[key] - 1
