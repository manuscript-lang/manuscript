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
  MS_STATUS_ALREADY_EXISTS = 6,         /* a path or name that is already taken */
  MS_STATUS_NOT_EMPTY = 7,              /* a directory that still has entries */
  MS_STATUS_PERMISSION_DENIED = 8,      /* the host refused the operation */
  MS_STATUS_UNSUPPORTED = 9,            /* a format, algorithm or key size the native does not know */
  MS_STATUS_CLOSED = 10,                /* a handle that was closed */
  MS_STATUS_FAILED = 11,
  MS_STATUS_UNAVAILABLE = 12,           /* a resource that is not there now */
  MS_STATUS_TIMED_OUT = 13,             /* a wait that ran out of time */
  MS_STATUS_OUTPUT_LIMIT = 14,          /* output past the caller's limit */
  MS_STATUS_NOT_TERMINAL = 15,          /* a descriptor that is not a terminal */
  MS_STATUS_NONE = 16,                  /* nothing to report: a watched root that is gone */
  MS_STATUS_BUSY = 17,                  /* a resource in use */
  MS_STATUS_AUTHENTICATION_FAILED = 18, /* a tag or signature that does not verify */
  MS_STATUS_NAME_TOO_LONG = 19,         /* a file name or path past the host's limit */
  MS_STATUS_LINK_LOOP = 20,             /* too many symbolic links on a path */
  MS_STATUS_NO_SPACE = 21,              /* the device is full */
  MS_STATUS_READ_ONLY = 22,             /* a read-only file system */
  MS_STATUS_CROSS_DEVICE = 23,          /* a link or rename across devices */
  MS_STATUS_TOO_MANY_OPEN = 24,         /* the process or system has no file descriptors left */
  /* The calling task was cancelled while the native waited. Runtime C returns it like any failure, freeing what it
   * holds; compiled code never sees it as an error: the task ends where the status arrives (msstd_status_error). */
  MS_STATUS_CANCELLED = 25
} MsStatus;

#endif
