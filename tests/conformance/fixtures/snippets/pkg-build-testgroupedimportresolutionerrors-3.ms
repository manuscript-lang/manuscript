# conform: tags=diagnostics,modules,records,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:592 TestGroupedImportResolutionErrors
from "@std/collections.ms" import MapBuilder

type MapBuilder:
    value: Int
