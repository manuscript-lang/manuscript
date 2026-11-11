// conform: tags=testing,tier-core
// conform: phase=check
type PrivateId:
	value: String

export type PublicRecord:
	ids: List[PrivateId]
