export opaque type Vault[T]:
    secret: T

export type Open[T]:
    value: T

export fn vault() Vault[Int]:
    return Vault[Int](7)

export opaque type Choice:
    case Payload(value: Int)
    case Empty

export fn choice() Choice:
    return Choice.Payload(7)
