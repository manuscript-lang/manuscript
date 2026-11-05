export opaque enum Legacy[T = Int]:
    case   Ready(value: T)
    case Pending
    case case(value: String)
