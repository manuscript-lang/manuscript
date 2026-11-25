// conform: tags=diagnostics
// conform: phase=check
// A public contract.
export interface Run {
    fn first() Int
    fn second() Int
}
// The implementation.
impl Run for Runner {
    fn first() Int => return 1
    // Explain the second operation.
    fn second() Int {
        value := 2
        // Handle both outcomes.
        // Keep these comments together.
        match value {
            one => return 1
            // Fallback explanation.
            _ => {
                return 2
            }
        }
    }
}
// Application entry.
fn main() Int => return 0
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
