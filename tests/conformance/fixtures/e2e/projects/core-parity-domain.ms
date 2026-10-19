# conform: tags=diagnostics,records,strings,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/core_parity/domain.ms
export type Key:
    id: Int
    label: String

export type Cause:
    count: Int
