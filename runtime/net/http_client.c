/* Request rules both protocols share (http_client.h). */
#include "http_client.h"

#include <string.h>

#include "ms_rt/chars.h"

static bool is_one_of(MsBytes name, const char *const *names, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (ms_ascii_equal_fold(name, ms_bytes_of((const uint8_t *)names[i], strlen(names[i])))) {
            return true;
        }
    }
    return false;
}

bool ms_http_field_refused(MsBytes name, bool http2) {
    static const char *const written[] = {"host", "content-length", "transfer-encoding"};
    static const char *const connection_specific[] = {"connection", "keep-alive", "proxy-connection", "upgrade"};
    return is_one_of(name, written, sizeof written / sizeof written[0]) ||
           (http2 && is_one_of(name, connection_specific, sizeof connection_specific / sizeof connection_specific[0]));
}
