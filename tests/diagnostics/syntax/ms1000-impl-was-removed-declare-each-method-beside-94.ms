// conform: tags=diagnostics
// conform: phase=check
export enum Failure {
    NotFound
    Denied(reason String)
}
impl Error for Failure {
    fn message() String => "f"
}
export type Item {
    value: Int
}
export fn fail() Result[Int, Failure] => error(Failure.Denied("denied"))
// expect-error: MS1000 7:1-7:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 11:10-11:11 remove the ':' between 'value' and its type; write value Type
// expect-fix: 11:10-11:11 ""
