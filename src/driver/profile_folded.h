/* driver/profile_folded.h: what `ms profile` does with the stacks the runtime wrote: read the folded text, rank the
 * functions, render the text report, and encode the pprof protobuf. Port of the conversion half of
 * crates/ms-cli/src/profile.rs. Every text lives in the arena. */
#ifndef MS_DRIVER_PROFILE_FOLDED_H
#define MS_DRIVER_PROFILE_FOLDED_H

#include "base/arena.h"
#include "base/intern.h"
#include "base/strbuild.h"

enum { MS_PROFILE_DEFAULT_HZ = 99, MS_PROFILE_DEFAULT_TOP = 20, MS_PROFILE_LOW_SAMPLES = 100 };

MS_LIST_DEFINE(MsU32List, ms_u32_list, uint32_t)
MS_LIST_DEFINE(MsU64List, ms_u64_list, uint64_t)

/* Sampled stacks, outermost frame first. Stack `s` is `frames[first[s] .. first[s] + length[s])`, frame names interned
 * in `names`; `counts[s]` is its sample count. Equal stacks are summed, in the order first seen. */
typedef struct MsFoldedProfile {
  uint64_t hz;
  MsNames names;
  MsU32List frames;
  MsU32List first;
  MsU32List length;
  MsU64List counts;
  uint64_t total;
} MsFoldedProfile;

/* Reads the runtime's folded text: `frame;frame count` lines, `#` comments, and the header `# hz=<n>`. False with
 * `error` set (a line number and what is wrong) when a line is malformed. */
bool ms_folded_parse(MsArena *arena, MsSpan text, MsFoldedProfile *out, MsSpan *error);
void ms_folded_free(MsFoldedProfile *profile);

/* A function's samples: its own (`flat`) and those of every stack it appears in (`cum`, counted once per stack). */
typedef struct MsTopEntry {
  MsName function;
  uint64_t flat;
  uint64_t cum;
} MsTopEntry;
MS_LIST_DEFINE(MsTopList, ms_top_list, MsTopEntry)

/* The functions ordered by flat samples, then cumulative, then name. */
void ms_folded_top(const MsFoldedProfile *profile, MsTopList *out);

uint64_t ms_folded_period_nanos(const MsFoldedProfile *profile);

/* The text report of the `top` busiest functions. */
void ms_folded_render_top(const MsFoldedProfile *profile, const MsTopList *entries, size_t top, MsStrBuild *out);

/* A percentage in hundredths (`4545` is 45.45%), rounded to nearest. */
uint64_t ms_percent_hundredths(uint64_t part, uint64_t total);

/* The profile as a pprof `profile.proto` message, uncompressed, which pprof and speedscope read. */
void ms_folded_encode_pprof(const MsFoldedProfile *profile, uint64_t time_nanos, MsStrBuild *out);

#endif
