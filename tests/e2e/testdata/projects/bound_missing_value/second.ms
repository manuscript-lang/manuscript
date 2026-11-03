export fn second(value: Int?) Int!Error:
    let convert = value.ok_or[Error]
    let copied = convert
    return copied()
