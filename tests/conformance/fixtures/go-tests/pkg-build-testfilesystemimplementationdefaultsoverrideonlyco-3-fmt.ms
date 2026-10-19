# conform: tags=control-flow,faults,formatter,interfaces,modules,parser,records,stdlib-faults,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/build/filesystem_defaults_test.go:94 TestFilesystemImplementationDefaultsOverrideOnlyConcreteCalls
import panic from "@std/faults.ms"
type Override:
    received: Bool
impl FileSystem for Override:
