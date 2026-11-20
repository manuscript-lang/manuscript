/* The embedded standard library: the generated table (std_embed_data.inc, written by
 * compiler/tools/std_embed_gen.c) behind ms_std_embedded. It sits outside libms.c so the tool
 * archives, which carry no standard library, do not grow by it. */
#include "ms/std_embed.h"

#include "std_embed_data.inc"

const MsStdFile *ms_std_embedded(uint32_t *count) {
    *count = std_embedded_count;
    return std_embedded;
}
