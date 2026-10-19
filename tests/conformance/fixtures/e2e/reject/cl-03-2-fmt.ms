# conform: tags=formatter,lists,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/reject/cl-03-2.ms
type PrivateId:
    value: String

export type PublicRecord:
    ids: List[PrivateId]
