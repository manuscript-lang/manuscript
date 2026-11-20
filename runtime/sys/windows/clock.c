#include "ms_rt/sys.h"

__declspec(dllimport) int __stdcall QueryPerformanceCounter(int64_t *v);
__declspec(dllimport) int __stdcall QueryPerformanceFrequency(int64_t *v);

int64_t ms_sys_monotonic_ns(void) {
    int64_t freq = 0, now = 0;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&now);
    if (freq < 1) {
        freq = 1;
    }
    /* Split so now * 1e9 cannot overflow after long uptimes. */
    return (now / freq) * 1000000000 + (now % freq) * 1000000000 / freq;
}
