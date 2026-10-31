export type Plain:
    n: Int

export opaque type Opaque:
    n: Int

export let (
    LOW = 1
    HIGH = 2
)

export fn read() Int:
    return LOW

export interface Measure:
    fn size() Int

export extern fn native() Int
