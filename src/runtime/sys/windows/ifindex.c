/* Windows keys interfaces by LUID and libuv reports their friendly names, which if_nametoindex does not take, so no
 * name has an index here; callers number the interfaces themselves. */
#include "ms_rt/sys.h"

uint32_t ms_sys_interface_index(const char *name) {
    (void)name;
    return 0;
}
