export interface Read:
    fn read() Int

export type Reader:
    operation: fn() Int

export fn invoke[T: Read](value: T) Int: value.read()
