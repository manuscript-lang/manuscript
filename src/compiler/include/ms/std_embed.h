/* The standard library the `ms` executable carries: the .ms files of src/stdlib/, embedded at build time. */
#ifndef MS_STD_EMBED_H
#define MS_STD_EMBED_H

#include "ms/stdlib.h"

/* Every bundled file in file-name order (the files of src/stdlib/core/ named flat), ready for
 * ms_std_load. Static storage; *count receives the number of files. */
const MsStdFile *ms_std_embedded(uint32_t *count);

#endif
