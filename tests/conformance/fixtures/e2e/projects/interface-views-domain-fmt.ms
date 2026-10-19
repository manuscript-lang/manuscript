# conform: tags=closures,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/interface_views/domain.ms
export interface Read:
    fn read() Int

export type Reader:
    operation: fn() Int

export fn invoke[T: Read](value: T) Int: value.read()
