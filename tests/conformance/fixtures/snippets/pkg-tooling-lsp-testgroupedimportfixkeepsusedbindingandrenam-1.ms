# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:344 TestGroupedImportFixKeepsUsedBindingAndRenameUsesNameOffsets
import {first, second} from "./helper.ms"

fn answer() Int:
    return first()
