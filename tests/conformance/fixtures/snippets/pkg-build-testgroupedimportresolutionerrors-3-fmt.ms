# conform: tags=formatter,modules,parser,records,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:592 TestGroupedImportResolutionErrors
import MapBuilder from "@std/collections.ms"

type MapBuilder:
    value: Int
