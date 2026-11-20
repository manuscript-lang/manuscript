/* The system's index of a network interface. Declares the one C library function it calls by hand, so no header is
 * needed (see ms_rt/base.h). */
#include "ms_rt/sys.h"

unsigned int if_nametoindex(const char *name);

uint32_t ms_sys_interface_index(const char *name) { return if_nametoindex(name); }
