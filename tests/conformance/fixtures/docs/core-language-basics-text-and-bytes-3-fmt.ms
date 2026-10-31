# conform: tags=closures,formatter,generics,interpolation,parser,strings,testing,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/basics/text-and-bytes.md:52
fn text[T](value: T) String:
    return value.to_string()

test "string conversion":
    let count = 3
    let convert: fn() String = count.to_string
    let _direct = count.to_string()
    let _bound = convert()
    let _embedded = "{count}"
