/* How the Windows sys files declare the Win32 functions they call: by hand, so no Windows header is needed.
 * Handles travel as uintptr_t, the integer they are. Off Windows the calling-convention macros are empty so the
 * linter's clang on Linux can still read the files. */
#ifndef MS_SYS_WINDOWS_WINAPI_H
#define MS_SYS_WINDOWS_WINAPI_H

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#define MS_WINAPI __declspec(dllimport) __stdcall
#define MS_WINAPI_CALLBACK __stdcall
#else
#define MS_WINAPI
#define MS_WINAPI_CALLBACK
#endif

// NOLINTBEGIN(readability-identifier-naming): the names are Win32's
MS_WINAPI void *VirtualAlloc(void *address, size_t length, uint32_t kind, uint32_t protection);
MS_WINAPI int VirtualFree(void *address, size_t length, uint32_t kind);
MS_WINAPI int SwitchToThread(void);
// NOLINTEND(readability-identifier-naming)

#endif
