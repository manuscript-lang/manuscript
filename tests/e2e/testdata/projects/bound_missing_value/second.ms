export fn second(value: Int?) Int!MissingValue:
    let convert = value.ok_or[MissingValue]
    let copied = convert
    return copied()
