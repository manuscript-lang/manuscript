[Wiki](../index.md) › [Repository maintenance](index.md)

# Pages deployment and Pages administration have different permissions

Verified: the built-in workflow token with Pages write permission can deploy artifacts, but GitHub rejected changing the existing site's build type through the settings REST endpoint with HTTP 403. Keep deployment on the standard configure/deploy actions; switching the repository's Pages source is an administrator action.

Decision: the user switched Pages to GitHub Actions and requested removal of obsolete Jekyll support. Publish Hugo output through the artifact workflow; no branch-publishing marker is needed. Historical workflow runs do not configure future publishing.

Apply when: migrating or repairing Pages publishing.
Evidence: [failed settings request](https://github.com/manuscript-lang/manuscript/actions/runs/38275457893/job/114902462365), [artifact deployment](../../.github/workflows/cicd.yml), and [publishing instructions](../../documentation/contributing/development.md).
Verify: inspect the actual deployment result, not just the book artifact or merged PR; confirm Pages source is GitHub Actions.
