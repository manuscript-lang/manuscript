/* Binding sets for the ownership pass's backward walks (ms/ownership.h). */
#include "ms/ownership.h"

#include <string.h>

static uint32_t bits_words(uint32_t nbits) {
    return (nbits + 63) / 64;
}

MsBits ms_bits_new(MsArena *a, uint32_t nbits) {
    MsBits s = {NULL, nbits};
    uint32_t n = bits_words(nbits);
    s.words = MS_NEW_N(a, uint64_t, n > 0 ? n : 1);
    memset(s.words, 0, sizeof(uint64_t) * (n > 0 ? n : 1));
    return s;
}

MsBits ms_bits_copy(MsArena *a, MsBits s) {
    MsBits out = ms_bits_new(a, s.nbits);
    memcpy(out.words, s.words, sizeof(uint64_t) * bits_words(s.nbits));
    return out;
}

bool ms_bits_has(MsBits s, uint32_t i) {
    return i < s.nbits && (s.words[i / 64] >> (i % 64) & 1) != 0;
}

void ms_bits_add(MsBits s, uint32_t i) {
    if (i < s.nbits) {
        s.words[i / 64] |= (uint64_t)1 << (i % 64);
    }
}

void ms_bits_remove(MsBits s, uint32_t i) {
    if (i < s.nbits) {
        s.words[i / 64] &= ~((uint64_t)1 << (i % 64));
    }
}

void ms_bits_clear(MsBits s) {
    memset(s.words, 0, sizeof(uint64_t) * bits_words(s.nbits));
}

uint32_t ms_bits_count(MsBits s) {
    uint32_t n = 0;
    for (uint32_t w = 0; w < bits_words(s.nbits); w++) {
        n += (uint32_t)__builtin_popcountll(s.words[w]);
    }
    return n;
}

void ms_bits_meet(MsBits into, MsBits from) {
    for (uint32_t w = 0; w < bits_words(into.nbits); w++) {
        into.words[w] &= w < bits_words(from.nbits) ? from.words[w] : 0;
    }
}

void ms_bits_union(MsBits into, MsBits from) {
    uint32_t n = bits_words(into.nbits) < bits_words(from.nbits) ? bits_words(into.nbits) : bits_words(from.nbits);
    for (uint32_t w = 0; w < n; w++) {
        into.words[w] |= from.words[w];
    }
}
