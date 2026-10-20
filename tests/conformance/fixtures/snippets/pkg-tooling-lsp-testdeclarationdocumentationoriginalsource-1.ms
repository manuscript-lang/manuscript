# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/documentation_test.go:28 TestDeclarationDocumentationOriginalSource
# α😀 heading
#
# second line
fn documented() Int: 1
# detached

fn blank() Int: 2
# ordinary
fn first() Int: 3
fn bare() Int: 4
# neighboring recovered declaration
fn neighbor() Int: 5
fn broken(
