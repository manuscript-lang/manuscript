# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:48 TestLibraryErrorDomainsAreDistinct
def wrong() -> Result[Unit, JsonError]:
    return error(cause: EncodingError.InvalidData)
