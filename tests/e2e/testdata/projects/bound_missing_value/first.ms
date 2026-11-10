export fn first(value: Int?) Int!Error:
    convert := value.ok_or[Error]
    return convert()
