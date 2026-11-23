# Public suffix data for libpsl

`suffixes_dafsa.h` is the Mozilla public suffix list (MPL-2.0, https://publicsuffix.org) compiled into the compact table libpsl
reads. It is generated, not edited. The list changes every few days; refresh it with:

```sh
curl -fsSL -o /tmp/public_suffix_list.dat https://publicsuffix.org/list/public_suffix_list.dat
python3 src/third_party/libpsl/src/psl-make-dafsa --output-format=cxx+ /tmp/public_suffix_list.dat src/third_party/libpsl_data/suffixes_dafsa.h
```

Current table: list VERSION 2026-11-21_04-33-45_UTC, COMMIT 87a2c1b8de5886a133ff4da21b2aa6fec88d8739,
sha256 of the downloaded list 017501d3fa7911c60ac7e0f68df4122b07216c585c15dc30e0f0c74b8d13a2b9.
Update this paragraph with the refresh. The generator is Python and runs only for the refresh, never in the build.
