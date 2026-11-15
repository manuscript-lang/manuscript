[Wiki](../index.md) › [Testing and conformance](index.md)

# Format parsers run the published suites

Verified: random differential tests against Python found no value bugs in JSON, base64, CSV, URL, time or TOML, but the official yaml-test-suite found nine invalid inputs accepted, a tab after `---` read as text, and over a hundred valid inputs rejected. Published suites find what generated inputs do not.

Each format gets a project fixture under `tests/conformance/fixtures/e2e/projects/<format>_suite/` that embeds the vendored suite data (test data only, with its license) and runs every case in one test. A case outside `data/expect-fail.txt` must pass; a case inside it must still fail, so fixing a case means deleting its line. The list names the reason and only shrinks. Do not add a line to make a failure go away: fix the parser, or record why the case cannot be supported (for example a non-string mapping key in a `Map[String, _]` model).

Apply when: changing a format parser in `stdlib/data/`, or adding a format suite.
Decision: JSON rejects a repeated object name even though RFC 8259 only says names SHOULD be unique, so two JSONTestSuite `y_` cases are listed as intentional.

Suites in the repository: `yaml_suite` (yaml-test-suite), `json_suite` (JSONTestSuite `y_` and `n_`; the `i_` implementation-defined files are not run).
Evidence: [yaml_suite](../../tests/conformance/fixtures/e2e/projects/yaml_suite/conformance_test.ms), [json_suite](../../tests/conformance/fixtures/e2e/projects/json_suite/conformance_test.ms).
Verify: `ms test tests/conformance/fixtures/e2e/projects/<format>_suite/ms.toml`.
