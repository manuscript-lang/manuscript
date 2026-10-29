# conform: tags=closures,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/interface_views/domain.ms
export interface Read:
    fn read() Int

export type Reader:
    operation: fn() Int

export fn invoke[T: Read](value: T) Int: value.read()
