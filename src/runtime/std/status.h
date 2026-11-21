/* runtime/std/status.h: the status codes the std natives return beyond abi/status.h. The numbers are the
 * catalogue's (the generated code reads them); they belong in abi/status.h, whose owner can move them there.
 */
#ifndef MS_RUNTIME_STD_STATUS_H
#define MS_RUNTIME_STD_STATUS_H

#include "abi/status.h"

enum {
  MS_STATUS_NOT_FOUND = 5,              /* a name, path or process that does not exist */
  MS_STATUS_PERMISSION_DENIED = 8,      /* the host refused the operation */
  MS_STATUS_UNSUPPORTED = 9,            /* a format, algorithm or key size the native does not know */
  MS_STATUS_AUTHENTICATION_FAILED = 18, /* a tag or signature that does not verify */
};

#endif
