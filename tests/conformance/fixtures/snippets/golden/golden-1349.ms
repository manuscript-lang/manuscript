// conform: tags=diagnostics
// conform: phase=check
export enum Failure:
    NotFound
    Denied(reason: String)
impl Error for Failure:
    fn message() String: "f"
export type Item:
    value: Int
export fn fail() Result[Int, Failure]: error(Failure.Denied("denied"))
