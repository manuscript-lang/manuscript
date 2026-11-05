export opaque type Legacy[T = Int]:
    case   Ready(value: T)
    case Pending
    case case(value: String)
