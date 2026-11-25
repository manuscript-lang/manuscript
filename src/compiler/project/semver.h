/* compiler/project/semver.h: semantic versions and the requirements a dependency names, as Cargo reads them.
 *
 * A version is MAJOR.MINOR.PATCH with an optional -pre suffix. A requirement is a version of one to three
 * numbers, optionally behind ^ (the default), ~ or =. Requirements that could span incompatible releases (^0,
 * ^0.0) are rejected, so every requirement lies inside one bucket and one copy per bucket is enough. */
#ifndef MS_PROJECT_SEMVER_H
#define MS_PROJECT_SEMVER_H

#include "base/arena.h"
#include "base/safe.h"
#include "base/strbuild.h"

typedef struct MsVersion {
  uint64_t major, minor, patch;
  const MsSpan *pre; /* the dot-separated pre-release identifiers; none for a release */
  size_t npre;
} MsVersion;

typedef enum MsBucketKind { MS_BUCKET_MAJOR, MS_BUCKET_MINOR, MS_BUCKET_PATCH } MsBucketKind;

/* The versions that may share one copy: `1.x` for a major of 1 or more, `0.4.x` for a zero major, and one
 * exact version for `0.0.x`. */
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
  const MsSpan *pre;
  size_t npre;
} MsRequirement;

/* `1.2.3` or `1.2.3-rc.1`, with no `v` and no build metadata. On failure `*why` is the message. */
MS_NODISCARD bool ms_version_parse(MsArena *arena, MsSpan text, MsVersion *out, MsSpan *why);
/* The version a git tag names: `v1.4.2` and `1.4.2` both name 1.4.2; anything else names none. */
MS_NODISCARD bool ms_version_of_tag(MsArena *arena, MsSpan tag, MsVersion *out);
MsBucket ms_version_bucket(const MsVersion *version);
int ms_version_compare(const MsVersion *a, const MsVersion *b);
void ms_version_append(MsStrBuild *out, const MsVersion *version);

MS_NODISCARD bool ms_requirement_parse(MsArena *arena, MsSpan text, MsRequirement *out, MsSpan *why);
MsBucket ms_requirement_bucket(const MsRequirement *requirement);
bool ms_requirement_matches(const MsRequirement *requirement, const MsVersion *version);
/* The form error messages use: `^1.2`, `~1.2.3`, `=0.4.1`. */
void ms_requirement_append(MsStrBuild *out, const MsRequirement *requirement);

bool ms_bucket_equal(MsBucket a, MsBucket b);

#endif
