/* Fetching the pinned toolchain archives (`lld`, the LLVM tools) on first use: the replacement of the Rust
 * `crates/ms-build/src/link/fetch.rs`. One HTTPS GET with libcurl (redirects, an HTTPS_PROXY, retries with a
 * growing pause), a SHA-256 check against the pinned digest, and an unpack of the named `bin/` files from the gzipped
 * tar into `<cache_root>/<name>/<first 16 digits of the digest>/`, staged beside the destination so concurrent
 * builds never see a partial file. Standalone: no scheduler and no runtime, only libcurl, OpenSSL's digest and zlib. */
#ifndef MS_BUILD_FETCH_H
#define MS_BUILD_FETCH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ms_rt/safe.h"

typedef struct MsFetchOptions {
    const char *name;          /* the cache subdirectory, such as "llvm" */
    const char *url;           /* the pinned archive (.tar.gz) */
    const char *sha256;        /* its SHA-256, 64 lowercase hexadecimal digits */
    const char *const *files;  /* the tools to unpack from the archive's bin/, without a ".exe" suffix */
    size_t nfiles;
    const char *cache_root;    /* the directory that holds <name>/ */
    const char *roots_pem;     /* borrowed: PEM roots to trust instead of the system's, or NULL for the system's */
    unsigned attempts;         /* downloads to try; 0 means 4 */
    void (*pause)(unsigned n); /* runs before attempt n + 1; NULL sleeps n seconds */
    bool announce;             /* tell stderr "ms: fetching <name> (once)" before downloading */
} MsFetchOptions;

enum { MS_FETCH_PATH = 1024, MS_FETCH_WHY = 512 };

/* Makes sure the tools are unpacked and writes their directory to `dir`. On failure `why` is the reason, in the
 * words "cannot <what> <name> into <dir>: <cause>". A directory with its `.ok` marker and every file is used as it
 * is, without touching the network. */
MS_NODISCARD MS_NONNULL bool ms_fetch_tools(const MsFetchOptions *options, char dir[MS_FETCH_PATH], char why[MS_FETCH_WHY]);

/* The downloaded body of `url`. `*body` is malloc'd (the caller frees it). Follows up to five redirects, honors the
 * HTTPS_PROXY and https_proxy environment variables, and retries a connection failure or a 5xx or 429 answer. */
MS_NODISCARD MS_NONNULL bool ms_fetch_get(const MsFetchOptions *options, const char *url, uint8_t **body, size_t *length,
                                          char why[MS_FETCH_WHY]);

/* Writes the files of the gzipped tar `archive` that sit under bin/ and are named in `wanted` into `dir`, executable,
 * under their base names. False, with `why`, when one is missing or the archive is malformed. */
MS_NODISCARD MS_NONNULL bool ms_fetch_unpack(const uint8_t *archive, size_t length, const char *const *wanted, size_t nwanted,
                                             const char *dir, char why[MS_FETCH_WHY]);

/* The lowercase hexadecimal SHA-256 of `data`. */
MS_NONNULL_ARGS(3) void ms_fetch_sha256_hex(const uint8_t *data, size_t length, char out[65]);

/* The system's trusted roots as one PEM text (malloc'd, `*length` bytes), or NULL when none can be read. */
MS_NONNULL char *ms_fetch_system_roots(size_t *length);

#endif
