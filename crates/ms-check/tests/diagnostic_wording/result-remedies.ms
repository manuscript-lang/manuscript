fn operation() Int!: return error(Error("failed"))

fn propagate() Int!:
    value := operation()?
    return ok(value)

fn recover() Int:
    if value := operation():
        return value
    else:
        return 0
