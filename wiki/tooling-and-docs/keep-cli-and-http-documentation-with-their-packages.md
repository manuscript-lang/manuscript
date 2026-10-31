[Wiki](../index.md) › [Tooling and docs](index.md)

# Keep CLI and HTTP documentation with their packages

Decision: the user explicitly removed the "Application hosts" section. CLI entry/accessor/shutdown contracts belong in the CLI package guide, and HTTP request/shutdown contracts belong in the HTTP package guide. Do not recreate a separate host category in the standard-library navigation.


Apply when: organizing the standard-library guide or adding application-entry documentation.
Evidence: [standard-library navigation](../../stdlib/intrinsics.ms), [CLI guide](../../stdlib/process.ms), [HTTP guide](../../stdlib/http.ms).
Verify: build the book with destination cleanup and confirm there is no standard-library/hosts route or sidebar section; existing entry and request links resolve to package pages.
