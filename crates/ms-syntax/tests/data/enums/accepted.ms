type Record:
    value: Int

enum Outcome[T = Int]:
    // Cases with and without data use the same declaration.
    case Success(value: T)
    case Failure

export opaque enum Hidden:
    case Secret(value: String)

opaque enum Private:
    case Internal
