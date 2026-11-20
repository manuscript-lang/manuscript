/* The @std/io natives over the host stream (stream.c): read, write and close of a handle, the redirect of a standard
 * stream, and the status of writing standard output. A failure of the transfer is STATUS_FAILED with its text. */
#include <stdio.h>

#include "ms_rt/io.h"
#include "stream.h"

uint8_t msstd_io_read(void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err) {
    MsFsFail fail = {0};
    MsFsBuffer data = {0};
    bool eof = false;
    uint8_t status = STATUS_OK;
    if (ms_stream_read(handle, has_max != 0, max, &data, &eof, &fail)) {
        if (eof) {
            status = STATUS_NONE;
        } else {
            msrt_write_bytes(out, data.data, data.length);
        }
        ms_fs_buffer_free(&data);
        return status;
    }
    return ms_fs_finish(&fail, err);
}

static uint8_t write_to(void *handle, MsBytes data, MsStr *err) {
    MsFsFail fail = {0};
    (void)ms_stream_write(handle, data, &fail);
    return ms_fs_finish(&fail, err);
}

uint8_t msstd_io_write_bytes(void *handle, const MsVec *data, MsStr *err) { return write_to(handle, ms_bytes_of(data->ptr, data->len), err); }

uint8_t msstd_io_write(void *handle, const MsStr *data, MsStr *err) { return write_to(handle, msrt_str_bytes(data), err); }

uint8_t msstd_io_close(void *handle, MsStr *err) {
    MsFsFail fail = {0};
    (void)ms_stream_close(handle, &fail);
    return ms_fs_finish(&fail, err);
}

enum { STANDARD_STREAMS = 3 };

/* Points standard stream `which` (0 input, 1 output, 2 error) at the null device. Pending buffered output is written
 * first. */
uint8_t msstd_io_redirect_null(int64_t which, MsStr *err) {
    MsFsFail fail = {0};
    if (which < 0 || which >= STANDARD_STREAMS) {
        ms_fs_fail_status(&fail, STATUS_INVALID_INPUT);
        return ms_fs_finish(&fail, err);
    }
    ms_sched_flush_stdout();
    const MsSysError error = ms_sys_fs_redirect_null((int32_t)which);
    if (error != 0) {
        char text[64];
        const int length = snprintf(text, sizeof text, "redirect standard stream: errno %d", (int)error);
        ms_fs_fail_text(&fail, length > 0 ? text : "redirect standard stream");
    }
    return ms_fs_finish(&fail, err);
}

/* The result of writing standard output: with `flush`, the buffered text is written first; the first write that
 * failed (a full disk, a closed descriptor) is returned as an error. */
uint8_t msstd_io_stdout_status(uint8_t flush, MsStr *err) {
    MsFsFail fail = {0};
    if (flush != 0) {
        ms_sched_flush_stdout();
    }
    const MsSysError code = ms_sched_stdout_error();
    if (code != 0) {
        ms_fs_fail_raw(&fail, code);
    }
    return ms_fs_finish(&fail, err);
}
