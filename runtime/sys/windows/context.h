/* The layout of the Win32 CONTEXT record, which the stack walker and the sampler read without a Windows header. */
#ifndef MS_SYS_WINDOWS_CONTEXT_H
#define MS_SYS_WINDOWS_CONTEXT_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* Offsets into CONTEXT of the instruction pointer, the stack pointer and the frame register, its size, and the
 * ContextFlags offset and value that ask for the control and integer registers. */
#if defined(__x86_64__)
enum { CONTEXT_BYTES = 0x4D0, CONTEXT_PC = 0xF8, CONTEXT_SP = 0x98, CONTEXT_FP = 0xA0, CONTEXT_FLAGS_AT = 0x30 };
enum { CONTEXT_CONTROL_INTEGER = 0x100003 };
#elif defined(__aarch64__)
enum { CONTEXT_BYTES = 0x390, CONTEXT_PC = 0x108, CONTEXT_SP = 0x100, CONTEXT_FP = 0xF0, CONTEXT_FLAGS_AT = 0 };
enum { CONTEXT_CONTROL_INTEGER = 0x400003 };
#else
#error "no CONTEXT layout for this architecture"
#endif

typedef struct {
    _Alignas(16) uint8_t bytes[CONTEXT_BYTES];
} Context;

static inline uintptr_t context_word(const Context *context, size_t offset) {
    uintptr_t word = 0;
    memcpy(&word, context->bytes + offset, sizeof word);
    return word;
}

#endif
