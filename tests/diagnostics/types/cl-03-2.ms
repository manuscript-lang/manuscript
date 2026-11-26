// conform: tags=testing,tier-core
// conform: phase=check
type PrivateId {
	value String
}

export type PublicRecord {
	ids List[PrivateId]
}
// expect-error: MS3000 7:8 public signature exposes private type PrivateId; add 'export' to its declaration or keep the function private
