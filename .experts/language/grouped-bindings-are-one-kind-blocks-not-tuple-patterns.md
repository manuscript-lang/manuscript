[Wiki](../index.md) › [Language](index.md)

# Grouped bindings are one-kind blocks, not tuple patterns

Decision: `let (` / `var (` declare several bindings of one kind, one entry per line, closing `)` aligned with the keyword; each entry is an ordinary binding (annotation or destructuring allowed) and sees earlier entries. Parenthesized patterns such as `let (a, b) = value` remain rejected, so a grouped block and a tuple pattern must stay distinguishable by the token after the keyword.

Apply when: changing binding grammar, formatter layout of declarations, or destructuring.
Evidence: [grouping rules](../../documentation/core-language/basics/bindings.md#grouping-bindings), [destructuring](../../documentation/core-language/types/destructuring.md), [module constants](../../documentation/core-language/modules/declarations.md), [binding groups fixture](../../tests/e2e/testdata/accept/binding-groups.ms).
Verify: `let (` entries evaluate in order with earlier ones in scope, `export let (` exports every entry, and `let (a, b) = pair` still fails with the not-a-binding-pattern diagnostic.
