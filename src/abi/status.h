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
  MS_STATUS_FAILED = 11
} MsStatus;

#endif
