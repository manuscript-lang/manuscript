export opaque type Vault[T]:
    secret: T

fn Vault[T].size() Int:
    return 1

export type Open[T]:
    value: T

export fn vault() Vault[Int]:
    return Vault[Int](7)

export opaque enum Choice:
    Payload(value: Int)
    Empty

export fn choice() Choice:
    return Choice.Payload(7)
