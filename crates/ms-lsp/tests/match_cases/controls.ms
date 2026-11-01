type Container:
    value: Int

type noneType:
    value: Int

fn optional(input: noneType?) Int:
    return 0

fn payload(input: Int?) Int:
    match input:
        value: return value
        none: return 0

fn chain(input: Container?) Int?:
    return input?.value

fn literal(value: Int) Int:
    match value:
        1: return 2
        _: return 0

fn conditional(value: Bool) Int:
    return if value: 1 else: 0
