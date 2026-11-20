/* The HTTP/1 server exchange natives of ms_rt/xchg.h. Placeholder: every call refuses with STATUS_UNSUPPORTED until the
 * exchange lands, so the contract in the header can be coded against. */
#include "ms_rt/xchg.h"

#include "../std/abi.h"

uint8_t msstd_xchg_next(const void *conn, int64_t head_limit, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    (void)conn; (void)head_limit; (void)has_timeout; (void)timeout; (void)out; (void)err;
    return STATUS_UNSUPPORTED;
}

int64_t msstd_xchg_reject_status(const void *conn) {
    (void)conn;
    return 0;
}

uint8_t msstd_xchg_reject(const void *conn, int64_t status, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    (void)conn; (void)status; (void)has_timeout; (void)timeout; (void)err;
    return STATUS_UNSUPPORTED;
}

void msstd_xchg_method(const void *exchange, MsStr *out) { (void)exchange; msrt_string_from_bytes(NULL, 0, out); }

void msstd_xchg_target(const void *exchange, MsStr *out) { (void)exchange; msrt_string_from_bytes(NULL, 0, out); }

void msstd_xchg_protocol(const void *exchange, MsStr *out) { (void)exchange; msrt_string_from_bytes(NULL, 0, out); }

void *msstd_xchg_headers(const void *exchange) {
    (void)exchange;
    return NULL;
}

uint8_t msstd_xchg_read(const void *exchange, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsVec *out, MsStr *err) {
    (void)exchange; (void)has_max; (void)max; (void)has_timeout; (void)timeout; (void)out; (void)err;
    return STATUS_UNSUPPORTED;
}

uint8_t msstd_xchg_send_head(const void *exchange, int64_t status, const void *headers, uint8_t has_length, int64_t length, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    (void)exchange; (void)status; (void)headers; (void)has_length; (void)length; (void)has_timeout; (void)timeout; (void)err;
    return STATUS_UNSUPPORTED;
}

uint8_t msstd_xchg_write(const void *exchange, const MsVec *data, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    (void)exchange; (void)data; (void)has_timeout; (void)timeout; (void)err;
    return STATUS_UNSUPPORTED;
}

uint8_t msstd_xchg_finish(const void *exchange, uint8_t has_timeout, int64_t timeout, uint8_t *keep, MsStr *err) {
    (void)exchange; (void)has_timeout; (void)timeout; (void)err;
    *keep = 0;
    return STATUS_UNSUPPORTED;
}

uint8_t msstd_xchg_reset(const void *exchange, int64_t max, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    (void)exchange; (void)max; (void)has_timeout; (void)timeout; (void)err;
    return STATUS_UNSUPPORTED;
}

void *msstd_xchg_share(const void *exchange) {
    (void)exchange;
    return NULL;
}

uint8_t msstd_xchg_take_conn(const void *exchange, void **out) {
    (void)exchange; (void)out;
    return STATUS_UNSUPPORTED;
}
