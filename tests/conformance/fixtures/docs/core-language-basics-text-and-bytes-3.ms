# conform: tags=closures,generics,interpolation,strings,testing,tier-core
# conform: phase=test
# conform: origin=documentation/core-language/basics/text-and-bytes.md:52
fn text[T](value: T) String:
    return value.to_string()

test "string conversion":
    let count = 3
    let convert: fn() String = count.to_string
    let direct = count.to_string()
    let bound = convert()
    let embedded = "{count}"
