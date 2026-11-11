[Wiki](../index.md) › [Tooling and docs](index.md)

# Source freshness does not establish published freshness

Verified: after the concurrency simplification, source declarations and generated Markdown were current while the checked-in website still exposed retired bounds and a removed module route. The user found this in the API reference. A source-generation check alone cannot verify the HTML, downloadable schemas, or search index that readers receive.

Apply when: removing or renaming public language/API surface, or reporting a documentation update complete.
Evidence: the user's follow-up to [the concurrency change](https://github.com/manuscript-lang/manuscript/pull/24); [publication checks](../../tests/docs/publication.test.cjs); [publishing workflow](../../.github/workflows/cicd.yml).
Verify: regenerate both reference sources and the website with destination cleanup; compare shipped schema downloads against current generated sources, reject obsolete module routes, and search rendered pages and search data for retired terminology. Confirm publication separately from a successful source merge.

Artifact cleanup must also retain explicitly requested reports inside the generated tree. Validate a coverage destination before retiring existing pages, and restore the report if cleanup removed it. The actual-binary `coverage_inside_artifacts_survives_regeneration` regression in [docgen tests](../../crates/ms-tooling/tests/guide_docgen.rs) checks report survival, stale-page retirement and preservation of existing pages when the report destination is invalid.

Verified again in the November 2026 language-doc audit: the `Error` declaration already used optional errno strings while promise, slice, and binary guides still named the retired categories; the ownership guide still called `Error` an interface and denied aggregate resource cleanup. Trace prose contracts as well as renamed symbols. Check cleanup against `crates/ms-lower/src/close.rs` and `tests/conformance/fixtures/e2e/stdlib/close-generic-wrapper.ms` and `tests/ownership-counts/destructure_omitted_resources.ms`; check borrowed results against `tests/conformance/fixtures/e2e/accept/borrowing-result-cases.ms`. A successful description-coverage gate does not validate those claims.
