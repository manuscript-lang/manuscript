/* Standard output on Windows: binary mode, so bytes reach the file or console unchanged. */
#include "runtime/sys/sys.h"

// NOLINTBEGIN(readability-identifier-naming): the names are the C runtime's
extern int _setmode(int fd, int mode);
// NOLINTEND(readability-identifier-naming)

enum { STDOUT_FD = 1, MODE_BINARY = 0x8000 };

void ms_sys_stdout_prepare(void) { (void)_setmode(STDOUT_FD, MODE_BINARY); }
