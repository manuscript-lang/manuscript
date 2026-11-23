/* runtime/core/drop_queue.h: bounded-stack drop and copy of recursive data (drop_queue.c). */
#ifndef MS_RUNTIME_CORE_DROP_QUEUE_H
#define MS_RUNTIME_CORE_DROP_QUEUE_H

#include <stddef.h>
#include <stdint.h>

/* ms-sig: msrt_drop_enter() -> i64 @end */
int64_t msrt_drop_enter(void);
/* ms-sig: msrt_drop_defer(run: *const u8, block: *mut u8) @end */
void msrt_drop_defer(void (*run)(uint8_t *block), uint8_t *block);
/* ms-sig: msrt_drop_leave() */
void msrt_drop_leave(void);
/* ms-sig: msrt_slot_copy_grown(copy: *const u8, src: *const u8, dst: *mut u8) */
void msrt_slot_copy_grown(void (*copy)(const uint8_t *src, uint8_t *dst), const uint8_t *src, uint8_t *dst);

#endif
