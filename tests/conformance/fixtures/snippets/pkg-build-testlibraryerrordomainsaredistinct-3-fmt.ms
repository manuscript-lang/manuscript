# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:51 TestLibraryErrorDomainsAreDistinct
def wrong() -> JsonError:
    return JsonError.PermissionDenied
