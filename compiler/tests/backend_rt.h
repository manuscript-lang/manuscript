/* The functions backend_rt.c defines for the generated programs to call. */
#ifndef MS_BACKEND_RT_H
#define MS_BACKEND_RT_H

#include <stdint.h>

typedef struct Str {
    uint8_t *ptr;
    uint64_t tagged;
} Str;

typedef struct List {
    uint8_t *ptr;
    uint64_t len;
    uint64_t cap;
} List;

long msrt_test_add(long a, long b);
void msrt_test_str(long n, Str *out);
void msrt_test_list(long n, List *out);
void msrt_test_ints(List *out);
void msrt_test_map(int64_t *out);
long msrt_test_mapsum(const int64_t *w);
long msrt_test_slen(const Str *s);
long msrt_test_len(const Str *s);
void msrt_string_clone(const Str *s, Str *out);
void msrt_string_free(const Str *s);
void *msrt_test_fn(void);
void *msrt_obj_clone(void *o);
void msrt_obj_drop(void *o);
void msrt_fault_int_overflow(void);
void msrt_cancelled(void);
void msrt_test_cancel(void);
void msrt_fault_int_range(void);
void msrt_fault_div_zero(void);
void msrt_fault_rem_zero(void);
void msrt_fault_div_overflow(long a, long b);
void msrt_index_fault(long a, long b);
long msrt_alloc(long n);
void msrt_free(long p);
long msmain(void);

#endif
