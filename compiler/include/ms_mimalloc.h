/* ms_mimalloc.h: the compiler allocates with mimalloc, as the runtime does. cmake/MsCompiler.cmake force-includes
 * this header into every compiler source (-include), so each malloc, calloc, realloc, free and strdup of a source
 * after it is mimalloc's and no source names the allocator. It includes no system header, so a source's own
 * feature macros still decide what the C library declares; those declarations then name mimalloc's functions,
 * which have the same types. Nothing here may include one (not even mimalloc.h, which includes <stdint.h>): the C
 * library fixes its feature set at its first header. */
#ifndef MS_MIMALLOC_H
#define MS_MIMALLOC_H

extern void *mi_malloc(__SIZE_TYPE__ size);
extern void *mi_calloc(__SIZE_TYPE__ count, __SIZE_TYPE__ size);
extern void *mi_realloc(void *block, __SIZE_TYPE__ size);
extern void mi_free(void *block);
extern char *mi_strdup(const char *text);
extern char *mi_strndup(const char *text, __SIZE_TYPE__ length);

#define malloc(size) mi_malloc(size)
#define calloc(count, size) mi_calloc(count, size)
#define realloc(block, size) mi_realloc(block, size)
#define free(block) mi_free(block)
#define strdup(text) mi_strdup(text)
#define strndup(text, length) mi_strndup(text, length)

#endif
