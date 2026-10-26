# Property testing

Properties from `@std/property.ms` check `insertion_sort` on generated lists.

```sh
ms test examples/property-testing/ms.toml            # 100 cases per property
ms test examples/property-testing/ms.toml --runs 1000
ms test examples/property-testing/ms.toml --fuzz 30s  # keep generating for 30s per property
ms test examples/property-testing/ms.toml --seed 1234 # replay a reported failure
```

Change `sorted.insert(at, n)` to `sorted.append(n)` in `src/main.ms` and rerun to see a shrunk counterexample.
