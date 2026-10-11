import List from "@std/collections.ms"

type PrivateId:
    value: String

export type PublicRecord:
    ids: List[PrivateId]
