# conform: tags=diagnostics,interfaces,testing,tier-core
# conform: phase=check
# conform: origin=pkg/build/filesystem_defaults_test.go:116 TestFilesystemImplementationDefaultsOverrideOnlyConcreteCalls
test "filesystem concrete overrides and interface defaults":
    let item = Override(false)
    let view = FileSystem(item)
