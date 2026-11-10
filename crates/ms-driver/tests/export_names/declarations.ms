export type Plain:
    n: Int

export opaque type Opaque:
    n: Int

export LOW := 1
export HIGH := 2

export fn read() Int:
    return LOW

export interface Measure:
    fn size() Int

export extern fn native() Int

export enum Color:
    Red
    Blue

export enum Outcome[T]:
    Value(value: T)
    Empty
