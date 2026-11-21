/* compiler/mir/mir_layout_internal.h: helpers shared by mir_shape.c and mir_layout.c. Not part of the layer's
 * interface. */
#ifndef MS_COMPILER_MIR_MIR_LAYOUT_INTERNAL_H
#define MS_COMPILER_MIR_MIR_LAYOUT_INTERNAL_H

#include "compiler/mir/mir_layout.h"

MS_LIST_DEFINE(MirLeafList, mir_leaf_list, MirLeaf)

/* Appends `leaves` to a scratch list, giving up (and marking the layouts failed) past the limit. */
void mir_layout_append(MirLayouts *layouts, MirLeafList *list, MsSpan leaves);

/* Moves a scratch list into the layouts' arena. */
MsSpan mir_layout_keep(MirLayouts *layouts, const MirLeafList *list);

/* The one word leaf, as a span. */
MsSpan mir_layout_one_word(void);

bool mir_layout_is_map_or_set(const MirTyData *data);

#endif
