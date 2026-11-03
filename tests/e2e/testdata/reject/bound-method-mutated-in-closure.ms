// A method value borrows its receiver for the call. A closure argument that changes the receiver
// is rejected after any statement of its body, not only the first; clone the receiver first
// (`values.clone().any`) to iterate a snapshot.
export fn main() Int:
    var values: Map[String, Int] = {"b": 2, "a": 1}
    var seen: List[String] = []
    let any_of = values.any

    let found = any_of(
        fn key,
        value:
            seen.append(key)
            values.remove("a")
            return value == 1
    )

    if found:
        return 1

    return 0
