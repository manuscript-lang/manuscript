# conform: tags=diagnostics,modules,records,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:592 TestGroupedImportResolutionErrors
import MapEntry from "@std/collections/collections.ms"

type MapEntry:
    value: Int
