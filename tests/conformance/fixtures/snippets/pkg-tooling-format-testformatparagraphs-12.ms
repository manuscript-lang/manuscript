# conform: tags=control-flow,diagnostics,interfaces,match,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:172 TestFormatParagraphs
# A public contract.
export interface Run:
    def first() -> Int
    def second() -> Int

# The implementation.
impl Run for Runner:
    def first() -> Int: return 1

    # Explain the second operation.
    def second() -> Int:
        let value = 2

        # Handle both outcomes.
        # Keep these comments together.
        match value:
            case one: return 1
            # Fallback explanation.
            case _:
                return 2

# Application entry.
def main() -> Int: return 0
