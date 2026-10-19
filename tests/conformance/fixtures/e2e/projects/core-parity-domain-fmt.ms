# conform: tags=formatter,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/core_parity/domain.ms
export type Key:
    id: Int
    label: String

export type Cause:
    count: Int
