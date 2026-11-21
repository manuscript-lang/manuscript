/* Child processes and directories of the build steps on Windows (ms/build_tool.h). Paths are UTF-8 and may use `/`. */
#include "ms/build_tool.h"

#if defined(_WIN32)

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Only kernel32 is used; the full header's macros (winspool's BIDI_TEXT, min, max) clash with names in the unity TU. */
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define NOGDI
#define NOUSER
#include <windows.h>

#include <direct.h>
#include <io.h>

/* `text` as a NUL-terminated UTF-16 string in `out` (WCHAR units). False when it is not valid UTF-8. */
static bool bw_wide(const char *text, MsBuf *out) {
    out->len = 0;
    const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
    if (n <= 0) {
        return false;
    }
    WCHAR *wide = ms_buf_push(out, (size_t)n * sizeof(WCHAR));
    return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, wide, n) == n;
}

/* `path` as a UTF-16 file name in `out`. A drive or UNC path of MAX_PATH or more characters gets the extended-length
 * prefix (`\\?\`, with `\` for `/`), which the file functions need beyond 260 characters; shorter paths are left alone. */
static bool bw_wide_path(const char *path, MsBuf *out) {
    if (!bw_wide(path, out)) {
        return false;
    }
    const WCHAR *wide = (const WCHAR *)out->data;
    const size_t n = out->len / sizeof(WCHAR) - 1;
    const bool drive = n >= 3 && wide[1] == L':' && (wide[2] == L'\\' || wide[2] == L'/');
    const bool unc = n >= 3 && wide[0] == L'\\' && wide[1] == L'\\' && wide[2] != L'?';
    if (n < 248 || (!drive && !unc)) {
        return true;
    }
    MsBuf prefixed = {0};
    static const WCHAR local[] = L"\\\\?\\";
    static const WCHAR share[] = L"\\\\?\\UNC\\";
    const WCHAR *head = unc ? share : local;
    const size_t head_len = unc ? 8 : 4;
    WCHAR *dest = ms_buf_push(&prefixed, (head_len + n + 1) * sizeof(WCHAR));
    memcpy(dest, head, head_len * sizeof(WCHAR));
    for (size_t i = unc ? 2 : 0; i < n; i++) {
        dest[head_len + i - (unc ? 2 : 0)] = wide[i] == L'/' ? L'\\' : wide[i];
    }
    dest[head_len + n - (unc ? 2 : 0)] = 0;
    ms_buf_free(out);
    *out = prefixed;
    return true;
}

/* One argument as the Microsoft C runtime reads it back: quoted when it holds a space, tab or quote, with backslashes
 * before a quote doubled. */
static void bw_quote(MsBuf *line, const char *arg) {
    const bool plain = arg[0] != 0 && strpbrk(arg, " \t\n\v\"") == NULL;
    if (plain) {
        ms_buf_puts(line, arg);
        return;
    }
    ms_buf_putc(line, '"');
    size_t backslashes = 0;
    for (const char *c = arg; *c != 0; c++) {
        if (*c == '\\') {
            backslashes++;
            continue;
        }
        if (*c == '"') {
            for (size_t i = 0; i < backslashes * 2 + 1; i++) {
                ms_buf_putc(line, '\\');
            }
        } else {
            for (size_t i = 0; i < backslashes; i++) {
                ms_buf_putc(line, '\\');
            }
        }
        backslashes = 0;
        ms_buf_putc(line, *c);
    }
    for (size_t i = 0; i < backslashes * 2; i++) {
        ms_buf_putc(line, '\\');
    }
    ms_buf_putc(line, '"');
}

void ms_build_errno_text(int err_no, MsBuf *out) {
    char message[128] = "unknown error";
    if (strerror_s(message, sizeof message, err_no) != 0) {
        (void)snprintf(message, sizeof message, "errno %d", err_no);
    }
    ms_buf_puts(out, message);
}

/* The system message of the Win32 error `code`. */
static void bw_error_text(DWORD code, MsBuf *out) {
    char message[256] = "";
    const DWORD n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, code, 0, message, sizeof message, NULL);
    size_t end = n;
    while (end > 0 && (message[end - 1] == '\r' || message[end - 1] == '\n' || message[end - 1] == ' ')) {
        end--;
    }
    if (end == 0) {
        ms_buf_printf(out, "error %lu", (unsigned long)code);
        return;
    }
    ms_buf_put(out, message, end);
}

bool ms_build_run(const char *what, const char *const *argv, const char *log, MsBuf *output) {
    return ms_build_run_in(what, argv, NULL, log, output);
}

bool ms_build_run_in(const char *what, const char *const *argv, const char *cwd, const char *log, MsBuf *output) {
    MsBuf line = {0}, wide_line = {0}, wide_log = {0}, wide_cwd = {0};
    for (size_t i = 0; argv[i] != NULL; i++) {
        if (i > 0) {
            ms_buf_putc(&line, ' ');
        }
        bw_quote(&line, argv[i]);
    }
    ms_buf_putc(&line, 0);
    bool ok = bw_wide(line.data, &wide_line) && bw_wide_path(log, &wide_log) && (cwd == NULL || bw_wide(cwd, &wide_cwd));
    SECURITY_ATTRIBUTES inherit = {sizeof inherit, NULL, TRUE};
    HANDLE out = INVALID_HANDLE_VALUE, in = INVALID_HANDLE_VALUE;
    if (ok) {
        out = CreateFileW((const WCHAR *)wide_log.data, GENERIC_WRITE, FILE_SHARE_READ, &inherit, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        in = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &inherit, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        ok = out != INVALID_HANDLE_VALUE && in != INVALID_HANDLE_VALUE;
    }
    DWORD code = 1;
    if (!ok) {
        ms_buf_printf(output, "cannot run %s: cannot prepare the command", what);
    } else {
        STARTUPINFOW startup;
        memset(&startup, 0, sizeof startup);
        startup.cb = sizeof startup;
        startup.dwFlags = STARTF_USESTDHANDLES;
        startup.hStdInput = in;
        startup.hStdOutput = out;
        startup.hStdError = out;
        PROCESS_INFORMATION process;
        memset(&process, 0, sizeof process);
        /* The command line buffer is writable: CreateProcessW may edit it. */
        if (!CreateProcessW(NULL, (WCHAR *)wide_line.data, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL,
                            cwd == NULL ? NULL : (const WCHAR *)wide_cwd.data, &startup, &process)) {
            ms_buf_printf(output, "cannot run %s: ", what);
            bw_error_text(GetLastError(), output);
            ok = false;
        } else {
            (void)WaitForSingleObject(process.hProcess, INFINITE);
            ok = GetExitCodeProcess(process.hProcess, &code) && code == 0;
            (void)CloseHandle(process.hProcess);
            (void)CloseHandle(process.hThread);
        }
    }
    if (out != INVALID_HANDLE_VALUE) {
        (void)CloseHandle(out);
    }
    if (in != INVALID_HANDLE_VALUE) {
        (void)CloseHandle(in);
    }
    if (!ok && output->len == 0) {
        ms_buf_printf(output, "%s failed: ", what);
        MsBuf text = {0};
        (void)ms_build_read(log, &text);
        size_t end = text.len;
        while (end > 0 && (text.data[end - 1] == '\n' || text.data[end - 1] == '\r' || text.data[end - 1] == ' ')) {
            end--;
        }
        ms_buf_put(output, text.data, end);
        ms_buf_free(&text);
    }
    ms_buf_free(&line);
    ms_buf_free(&wide_line);
    ms_buf_free(&wide_log);
    ms_buf_free(&wide_cwd);
    return ok;
}

bool ms_build_have(const char *name) {
    MsBuf wide = {0};
    bool found = false;
    if (bw_wide(name, &wide)) {
        found = SearchPathW(NULL, (const WCHAR *)wide.data, L".exe", 0, NULL, NULL) != 0;
    }
    ms_buf_free(&wide);
    return found;
}

/* Makes a directory from `pattern` (ending in XXXXXX): the six characters become a number from the process and a
 * counter, retried until the directory is new. */
bool ms_build_make_dir(char *pattern) {
    static unsigned counter;
    const size_t length = strlen(pattern);
    if (length < 6) {
        return false;
    }
    for (unsigned attempt = 0; attempt < 100; attempt++) {
        const unsigned value = (unsigned)GetCurrentProcessId() * 131u + (++counter) * 7919u + GetTickCount();
        (void)snprintf(pattern + length - 6, 7, "%06x", value & 0xffffffu);
        if (_mkdir(pattern) == 0) {
            return true;
        }
        if (errno != EEXIST) {
            return false;
        }
    }
    return false;
}

bool ms_build_make_path(const char *path) {
    char partial[4096];
    const size_t length = strlen(path);
    if (length >= sizeof partial) {
        return false;
    }
    memcpy(partial, path, length + 1);
    for (size_t i = 1; i <= length; i++) {
        if (partial[i] != '/' && partial[i] != '\\' && partial[i] != 0) {
            continue;
        }
        if (i == 2 && partial[1] == ':') {
            continue; /* `C:` is a drive, not a directory */
        }
        const char saved = partial[i];
        partial[i] = 0;
        if (_mkdir(partial) != 0 && errno != EEXIST) {
            return false;
        }
        partial[i] = saved;
    }
    return true;
}

void ms_build_unlink(const char *path) {
    MsBuf wide = {0};
    if (bw_wide_path(path, &wide)) {
        const WCHAR *name = (const WCHAR *)wide.data;
        (void)SetFileAttributesW(name, FILE_ATTRIBUTE_NORMAL); /* a read-only file would refuse to go */
        if (!DeleteFileW(name)) {
            (void)RemoveDirectoryW(name);
        }
    }
    ms_buf_free(&wide);
}

void ms_build_remove_tree(const char *path) {
    MsBuf pattern = {0}, wide = {0};
    ms_buf_printf(&pattern, "%s/*", path);
    ms_buf_putc(&pattern, 0);
    if (bw_wide(pattern.data, &wide)) {
        WIN32_FIND_DATAW found;
        HANDLE handle = FindFirstFileW((const WCHAR *)wide.data, &found);
        if (handle != INVALID_HANDLE_VALUE) {
            do {
                if (wcscmp(found.cFileName, L".") == 0 || wcscmp(found.cFileName, L"..") == 0) {
                    continue;
                }
                char name[1024];
                if (WideCharToMultiByte(CP_UTF8, 0, found.cFileName, -1, name, sizeof name, NULL, NULL) <= 0) {
                    continue;
                }
                MsBuf child = {0};
                ms_buf_printf(&child, "%s/%s", path, name);
                ms_buf_putc(&child, 0);
                if ((found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 && (found.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0) {
                    ms_build_remove_tree(child.data);
                } else {
                    ms_build_unlink(child.data);
                }
                ms_buf_free(&child);
            } while (FindNextFileW(handle, &found));
            (void)FindClose(handle);
        }
    }
    ms_build_unlink(path);
    ms_buf_free(&pattern);
    ms_buf_free(&wide);
}

#endif
