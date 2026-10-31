# conform: tags=alternatives,control-flow,formatter,interfaces,parser,records,strings,tier-core,scope-cleanup
# conform: phase=parse
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
    fn count() Int

impl Countable for Counter:
    # Returns the stored count.
    fn count() Int:
        return self.count

# Private declarations stay private.
type Hidden:
    # Hidden member documentation.
    value: Int
