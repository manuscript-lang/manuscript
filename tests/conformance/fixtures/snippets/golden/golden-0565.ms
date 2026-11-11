// conform: tags=diagnostics
// conform: phase=check
export interface Read:
    fn original() Int
export type Box[T: Read]:
    value: T
