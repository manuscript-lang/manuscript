// conform: tags=diagnostics
// conform: phase=check
// A described record.
export type Counter {
    // Current count in items.
    // May start at zero.
    count Int = 0
    // Detached description.

    undocumented Int = 1
}

export enum Outcome {
    // A completed count.
    Ready(value Int)
    // Work is pending.
    Pending
    // Work failed with source context.
    Failed(
        // Original failure diagnostic.
        message String
    )
}

export interface Countable {
    // Reads the count without mutation.
    fn count() Int
}

impl Countable for Counter {
    // Returns the stored count.
    fn count() Int {
        return self.count
    }
}

// Private declarations stay private.
type Hidden {
    // Hidden member documentation.
    value: Int
}
// expect-error: MS1000 30:1-30:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 40:10-40:11 remove the ':' between 'value' and its type; write value Type
// expect-fix: 40:10-40:11 ""
