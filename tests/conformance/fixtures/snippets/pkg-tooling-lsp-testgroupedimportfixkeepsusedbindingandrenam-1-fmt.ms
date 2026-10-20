# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:344 TestGroupedImportFixKeepsUsedBindingAndRenameUsesNameOffsets
import { first, second } from "./helper.ms"
fn answer() Int:
    return first()
