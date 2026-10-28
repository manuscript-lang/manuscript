# conform: tags=alternatives,control-flow,diagnostics,interfaces,records,strings,tier-core,scope-cleanup
# conform: phase=check
# conform: origin=pkg/checker/documentation_members_test.go:14 TestDocumentationCapturesMemberComments
# A described record.
export type Counter:
    # Current count in items.
    # May start at zero.
    count: Int = 0
    # Detached description.
    undocumented: Int = 1

export type Outcome:
    # A completed count.
    case Ready(value: Int)
    # Work is pending.
    case Pending
    # Work failed with source context.
    case Failed(
        # Original failure diagnostic.
        message: String
    )

export interface Countable:
    # Reads the count without mutation.
    def count() -> Int

impl Countable for Counter:
    # Returns the stored count.
    def count() -> Int:
        return self.count

# Private declarations stay private.
type Hidden:
    # Hidden member documentation.
    value: Int
