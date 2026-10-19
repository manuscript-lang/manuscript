# conform: tags=control-flow,formatter,interfaces,match,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:172 TestFormatParagraphs
# A public contract.
export interface Run:
    fn first() Int
    fn second() Int

# The implementation.
impl Run for Runner:
    fn first() Int: return 1

    # Explain the second operation.
    fn second() Int:
        let value = 2

        # Handle both outcomes.
        # Keep these comments together.
        match value:
            one: return 1
            # Fallback explanation.
            _:
                return 2

# Application entry.
fn main() Int: return 0
