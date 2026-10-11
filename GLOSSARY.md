# Manuscript

Terms used in the Manuscript language design.

## Functions and sharing

**Shared function**:
A function value whose type guarantees that its captures and bound receiver are safe for concurrent access. Sharing does not guarantee that captured resources remain open.
_Avoid_: Parallel function
