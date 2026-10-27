# JSON benchmark

`@std/json` `parse` and `stringify` against Node's `JSON.parse` and `JSON.stringify` (V8) on the standard documents `twitter.json`, `canada.json` and `citm_catalog.json` plus a small RPC message. `parse` builds a `JsonValue` tree and `stringify` writes one, which is the same work `JSON.parse` and `JSON.stringify` do on a JavaScript value.

```sh
cargo xtask runtime && cargo build --release --locked -p ms-cli
sh bench/perf/json/run.sh
```

`rust/` is the serde_json baseline (`Value`, `from_slice` and `to_vec`, release build) with the same protocol; `run.sh` prints the speed against Node and against serde_json. `fetch.sh` downloads the corpora into `data/` (not committed). `node.js` and `src/main.ms` use one protocol: a warm-up run, then the median of at least five runs and one second. The last two columns are how many times faster Manuscript is than each, so below `1.00x` the baseline wins.

For profiling, `ms run bench/perf/json/ms.toml -- quick twitter:doc` runs five iterations of one case; the operations are `parse`, `stringify`, and `doc` (build the parsed document and release it, without creating the `JsonValue` tree).
