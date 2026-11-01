export fn first(value: Int?) Int!MissingValue:
    let convert = value.ok_or[MissingValue]
    return convert()
