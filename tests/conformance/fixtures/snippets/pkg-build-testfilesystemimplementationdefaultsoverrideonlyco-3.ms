# conform: tags=control-flow,diagnostics,faults,interfaces,modules,records,stdlib-faults,tier-stdlib
# conform: phase=check
# conform: origin=pkg/build/filesystem_defaults_test.go:94 TestFilesystemImplementationDefaultsOverrideOnlyConcreteCalls
from "@std/core.ms" import panic

type Override:
    received: Bool

impl FileSystem for Override:
