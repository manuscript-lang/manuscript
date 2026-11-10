type Secret:
    value: Int

export type Public:
    value: Int

export fn hidden[T = Secret]() T?:
    return none

export type Container[T = List[Secret]]:
    value: T?

export interface Reader:
    fn read[T = Secret]() T?

export enum Choice[T = Secret]:
    Empty
    Value(value: T)

fn private_default[T = Secret]() T?:
    return none

export fn public_default[T = Public]() T?:
    return none

export fn earlier_default[T, U = T]() U?:
    return none
