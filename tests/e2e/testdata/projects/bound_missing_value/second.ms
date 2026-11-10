export fn second(value: Int?) Int!Error:
    convert := value.ok_or[Error]
    copied := convert
    return copied()
