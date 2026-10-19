# Differential tools

The Go implementation is the oracle until cutover. These scripts mutate the repository's `.ms` files and compare Go with `ms-syntax`; every mode must report `0 mismatches`.

```sh
make build                      # builds ./ms, the Go oracle
export MS_DIFF_WORK=/tmp/ms-diff CARGO_TARGET_DIR=$PWD/target
mkdir -p $MS_DIFF_WORK
go build -mod=vendor -o $MS_DIFF_WORK/oracle crates/ms-syntax/tools/oracle.go
cargo build -p ms-syntax

python3 crates/ms-syntax/tools/diff_parse.py  SEED PER_FILE   # first parse diagnostic vs `ms check --json`
python3 crates/ms-syntax/tools/diff_tree.py   SEED PER_FILE strict|partial   # full AST dump, strict and recovery
python3 crates/ms-syntax/tools/diff_format.py SEED PER_FILE   # formatted output vs `ms fmt`
```

`oracle.go` prints the canonical AST dump in the shape of `src/dump.rs`. `tests/data` holds fixtures recorded from the Go implementation by these tools (`*.src` so repository `.ms` checks ignore them).
