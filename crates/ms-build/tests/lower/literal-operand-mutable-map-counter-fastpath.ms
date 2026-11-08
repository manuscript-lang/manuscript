// expect-mir: "msrt_map_slot_lent"

export fn main() Int:
    var key = "long-dynamic-map-key-{1}"
    var values: Map[String, Int] = Map()
    values.add(key.clone(), values.get(key).get(0) + 1)
    key = "long-dynamic-map-key-{2}"
    values.add(key.clone(), values.get(key).get(0) + 1)
    return values["long-dynamic-map-key-1"] + values[key] - 2
