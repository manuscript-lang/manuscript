/* eq.h: the equality cycle guard (eq.c). Its ms-sig lines (`msrt_eq_enter(a: *const u8, b: *const u8) -> u8 @leaf`,
 * `msrt_eq_leave(a: *const u8, b: *const u8) @leaf`) and symbol entries arrive with the task flip, which deletes the
 * Rust definitions in desc.rs; a header under ms_rt would need them now. */
#ifndef MS_CORE_EQ_H
#define MS_CORE_EQ_H

#include <stdint.h>

/* Registers the pair of objects being compared: 1, or 0 when the pair is already being compared (a cycle, which
 * the comparison treats as equal). */
uint8_t msrt_eq_enter(const uint8_t *a, const uint8_t *b);
/* Ends the innermost registration. */
void msrt_eq_leave(const uint8_t *a, const uint8_t *b);

#endif
