# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/build/library_test.go:48 TestLibraryErrorDomainsAreDistinct
fn wrong() Unit!JsonError:
    return error(cause: EncodingError.InvalidData)
