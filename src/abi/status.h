/* abi/status.h: the status codes of fallible runtime natives. The numbers never change: generated code and
 * the standard library read them. */
#ifndef MS_ABI_STATUS_H
#define MS_ABI_STATUS_H

typedef enum MsStatus {
  MS_STATUS_OK = 0,
  MS_STATUS_INVALID_INPUT = 1,
  MS_STATUS_OUT_OF_RANGE = 2,
  MS_STATUS_LIMIT_EXCEEDED = 3,
  MS_STATUS_INVALID_DATA = 4,
  MS_STATUS_NOT_FOUND = 5,              /* a name, path or process that does not exist */
  MS_STATUS_PERMISSION_DENIED = 8,      /* the host refused the operation */
  MS_STATUS_UNSUPPORTED = 9,            /* a format, algorithm or key size the native does not know */
  MS_STATUS_FAILED = 11,
  MS_STATUS_AUTHENTICATION_FAILED = 18 /* a tag or signature that does not verify */
} MsStatus;

#endif
