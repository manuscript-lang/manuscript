export fn first(value: Int?) Int!Error:
    let convert = value.ok_or[Error]
    return convert()
