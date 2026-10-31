[Wiki](../index.md) › [Tooling and docs](index.md)

# Source freshness does not establish published freshness

Verified: after the concurrency simplification, source declarations and generated Markdown were current while the checked-in website still exposed retired bounds and a removed module route. The user found this in the API reference. A source-generation check alone cannot verify the HTML, downloadable schemas, or search index that readers receive.

Verified: integration can expose an API in an additional reference without changing its declaration. Adding Map to the prelude and then adding Map methods required regenerating the prelude page and both downloads as well as the collections page. GitHub tested the combined merge tree while the local branch still passed freshness; [the failed freshness gate](https://github.com/manuscript-lang/manuscript/actions/runs/38431272729) identified this drift. Run `make docs` and `make book-check` after latest-main integration, using the canonical registry rather than editing generated pages by hand.

Apply when: removing or renaming public language/API surface, or reporting a documentation update complete.
Evidence: the user's follow-up to [the concurrency change](https://github.com/manuscript-lang/manuscript/pull/24); [publication checks](../../tests/docs/publication.test.cjs); [publishing workflow](../../.github/workflows/cicd.yml).
Verify: regenerate both reference sources and the website with destination cleanup; compare shipped schema downloads against current generated sources, reject obsolete module routes, and search rendered pages and search data for retired terminology. Confirm publication separately from a successful source merge. Historical review text must not reintroduce syntax the user explicitly requested removing.
