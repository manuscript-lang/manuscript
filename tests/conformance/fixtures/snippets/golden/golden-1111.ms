// conform: tags=diagnostics
// conform: phase=check
// A public contract.
export interface Run:
    fn first() Int
    fn second() Int
// The implementation.
impl Run for Runner:
    fn first() Int: return 1
    // Explain the second operation.
    fn second() Int:
        value := 2
        // Handle both outcomes.
        // Keep these comments together.
        match value:
            one: return 1
            // Fallback explanation.
            _:
                return 2
// Application entry.
fn main() Int: return 0
