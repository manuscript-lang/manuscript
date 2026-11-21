/* Semantic versions and the requirements a dependency names, as Cargo reads them. Port of
 * crates/ms-driver/src/project/semver.rs.
 *
 * A version is `MAJOR.MINOR.PATCH` with an optional `-pre` suffix. A requirement is a version of one to three
 * numbers, optionally behind `^` (the default), `~` or `=`. Requirements that could span incompatible releases (`^0`,
 * `^0.0`) are rejected, so every requirement lies inside one bucket and one copy per bucket is enough. Texts that
 * parse failures return are the Rust ones. */
#ifndef MS_SEMVER_H
#define MS_SEMVER_H

#include "ms/base.h"

typedef struct MsVersion {
    uint64_t major, minor, patch;
    const char *pre; /* dot-separated pre-release identifiers, "" for a release */
} MsVersion;

/* The versions that may share one copy: `1.x` for a major of 1 or more, `0.4.x` for a zero major, one exact version
 * for `0.0.x`. */
typedef enum MsBucketKind { MS_BUCKET_MAJOR, MS_BUCKET_MINOR, MS_BUCKET_PATCH } MsBucketKind;

typedef struct MsBucket {
    MsBucketKind kind;
    uint64_t number;
} MsBucket;

typedef enum MsRequirementOp { MS_REQ_CARET, MS_REQ_TILDE, MS_REQ_EXACT } MsRequirementOp;

typedef struct MsRequirement {
    MsRequirementOp op;
    uint64_t major;
    bool has_minor, has_patch;
    uint64_t minor, patch;
    const char *pre;
} MsRequirement;

/* `1.2.3` or `1.2.3-rc.1`, with no `v` and no build metadata; on failure *error is the message. */
MS_NODISCARD bool ms_version_parse(MsArena *a, const char *text, MsVersion *out, const char **error);
/* The version a git tag names: `v1.4.2` and `1.4.2` both name 1.4.2; anything else names none. */
bool ms_version_of_tag(MsArena *a, const char *tag, MsVersion *out);
/* Negative, zero or positive, as semver orders versions (a pre-release is below its release). */
int ms_version_compare(const MsVersion *x, const MsVersion *y);
MsBucket ms_version_bucket(const MsVersion *v);
const char *ms_version_text(MsArena *a, const MsVersion *v);
bool ms_bucket_equal(MsBucket x, MsBucket y);
/* Total order of buckets: kind, then number (MAJOR before MINOR before PATCH). */
int ms_bucket_compare(MsBucket x, MsBucket y);
const char *ms_bucket_text(MsArena *a, MsBucket b);

MS_NODISCARD bool ms_requirement_parse(MsArena *a, const char *text, MsRequirement *out, const char **error);
MsBucket ms_requirement_bucket(const MsRequirement *r);
/* Whether `v` satisfies `r`; a pre-release satisfies it only when the requirement names one. */
bool ms_requirement_matches(const MsRequirement *r, const MsVersion *v);
const char *ms_requirement_text(MsArena *a, const MsRequirement *r);

#endif
