type Record:
    value: Int

enum Outcome[T = Int]:
    // Cases with and without data use the same declaration.
    Success(value: T)
    Failure

export opaque enum Hidden:
    Secret(value: String)

opaque enum Private:
    Internal
