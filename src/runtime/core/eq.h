/* The equality cycle guard: the program calls these around a comparison of two objects, by exported name. */
#ifndef MS_RUNTIME_CORE_EQ_H
#define MS_RUNTIME_CORE_EQ_H

#include <stdint.h>

/* ms-sig: msrt_eq_enter(a: *const u8, b: *const u8) -> u8 @leaf */
/* Registers the pair; 0 when it is already being compared (a cycle: the comparison assumes equal), else 1. */
uint8_t msrt_eq_enter(const uint8_t *a, const uint8_t *b);
/* ms-sig: msrt_eq_leave(a: *const u8, b: *const u8) @leaf */
/* Unregisters the pair the innermost enter registered. */
void msrt_eq_leave(const uint8_t *a, const uint8_t *b);

#endif
