#include <stdint.h>
#include <stddef.h>
typedef struct { unsigned char *p; size_t n; const char *kind, *message; } Result;
Result hex(const unsigned char*,size_t,int64_t);
Result b64(const unsigned char*,size_t,int64_t);
Result unhex(const unsigned char*,size_t,int64_t);
Result utf16le(const unsigned char*,size_t,int64_t);
Result utf16be(const unsigned char*,size_t,int64_t);
Result hexgrow(const unsigned char*,size_t,int64_t);

Result b64grow(const unsigned char*,size_t,int64_t);
