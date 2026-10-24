# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:51 TestLibraryErrorDomainsAreDistinct
def wrong() -> JsonError:
    return JsonError.PermissionDenied
