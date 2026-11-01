export opaque type Vault[T]:
    secret: T

export type Open[T]:
    value: T

export fn vault() Vault[Int]:
    return Vault[Int](7)
