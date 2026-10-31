[Wiki](../index.md) › [Runtime](index.md)

# YAML alias budgets count the expanded root once

Verified: the flow parser counts a value before reading an alias. Charging the entire anchor tree again counts its root twice and rejects exact `max_values` budgets. Charge only the remaining nodes before expansion. An accepted string alias used as a key contributes zero values, and final expanded-depth validation remains necessary.

Apply when: changing YAML flow parsing or its limits.
Evidence: [parser](../../stdlib/yaml.ms), [regressions](../../tests/e2e/testdata/stdlib/yaml-budget-regression.ms).
Verify: `[&a 1, *a]` accepts a value limit of 3 and rejects 2; nested aliases and alias keys obey exact budgets; an alias moved deeper still obeys the expanded-depth limit.
