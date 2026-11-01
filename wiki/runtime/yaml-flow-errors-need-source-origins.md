[Wiki](../index.md) › [Runtime](index.md)

# YAML diagnostics need source origins

Verified: a flow cursor is relative to its gathered value, not the complete source line. Reporting that offset as a column loses mapping, sequence, indentation and anchor prefixes; treating the whole cursor as one column loses physical line breaks. Capture the origin before gathering advances the context, carry its scalar column through prefix removal, and project the cursor through retained line feeds only when reporting an error. Keep virtual row/column shifts in separate diagnostic metadata rather than changing parsing bases. Merge failures and unsupported forms must use the same projection; locate rejected controls only on their error path. Valid input needs no per-character position tracking.

Apply when: changing YAML gathering, scalar prefixes, compact virtual source lines, or diagnostics. Root continuation uses `base - 1`, so the source origin must independently retain the original `base + 1` column. All prefix arithmetic uses scalar lengths.
Evidence: [parser](../../stdlib/data/yaml.ms), [source-origin regressions](../../tests/e2e/testdata/stdlib/yaml-error-location-regression.ms).
Verify: root controls, mapping/sequence/anchor prefixes, Unicode, retained comment line breaks and quoted EOF. Virtual document-marker rows and compact tab prefixes retain their diagnostic projection separately from parsing bases. Check same-row accumulation, later-row isolation, lazy merge failures, later-line unsupported constructs and invalid controls after Unicode. Parser bases, splicing and valid values stay unchanged.
