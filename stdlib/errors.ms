# Canonical standard-library declarations. Implementations are native.


export type LibraryError:
    case InvalidInput
    case InvalidData
    case OutOfRange
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case PermissionDenied
    case Unsupported
    case Closed
    case Timeout
    case AuthenticationFailed
    case Failed(message: String)
