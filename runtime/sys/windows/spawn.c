/* Running a program to completion on Windows: CreateProcessW with the standard streams on anonymous pipes. The error
 * pipe is drained on a helper thread so a program that fills one pipe cannot block on it. */
#include <windows.h>

#include <stdlib.h>
#include <string.h>

#include "ms_rt/sys_process.h"

enum { CHUNK = 4096 };

typedef struct Sink {
    HANDLE pipe;
    char *data;
    size_t length;
    size_t capacity;
    DWORD failure;
} Sink;

static bool sink_append(Sink *sink, const char *bytes, size_t count) {
    if (sink->length + count + 1 > sink->capacity) {
        size_t capacity = sink->capacity == 0 ? CHUNK : sink->capacity;
        while (sink->length + count + 1 > capacity) {
            capacity *= 2;
        }
        char *grown = realloc(sink->data, capacity);
        if (grown == NULL) {
            return false;
        }
        sink->data = grown;
        sink->capacity = capacity;
    }
    memcpy(sink->data + sink->length, bytes, count);
    sink->length += count;
    sink->data[sink->length] = '\0';
    return true;
}

/* Reads `sink->pipe` until the writer closes it. */
static DWORD WINAPI drain(LPVOID argument) {
    Sink *sink = argument;
    char chunk[CHUNK];
    for (;;) {
        DWORD count = 0;
        if (!ReadFile(sink->pipe, chunk, sizeof chunk, &count, NULL)) {
            const DWORD error = GetLastError();
            sink->failure = error == ERROR_BROKEN_PIPE ? 0 : error;
            return 0;
        }
        if (!sink_append(sink, chunk, count)) {
            sink->failure = ERROR_NOT_ENOUGH_MEMORY;
            return 0;
        }
    }
}

static WCHAR *wide_of(const char *text, size_t length) {
    const int units = length == 0 ? 0 : MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, (int)length, NULL, 0);
    if (length != 0 && units == 0) {
        return NULL;
    }
    WCHAR *wide = malloc(((size_t)units + 1) * sizeof *wide);
    if (wide != NULL) {
        if (units > 0) {
            (void)MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, (int)length, wide, units);
        }
        wide[units] = 0;
    }
    return wide;
}

/* The command line CreateProcess takes: each argument quoted so that the C runtime of the program reads it back. */
static WCHAR *command_line(char *const *argv) {
    size_t total = 1;
    for (size_t i = 0; argv[i] != NULL; i++) {
        total += 2 * strlen(argv[i]) + 3;
    }
    char *text = malloc(total);
    if (text == NULL) {
        return NULL;
    }
    size_t used = 0;
    for (size_t i = 0; argv[i] != NULL; i++) {
        const char *arg = argv[i];
        if (i > 0) {
            text[used++] = ' ';
        }
        const bool quote = arg[0] == 0 || strpbrk(arg, " \t\n\v\"") != NULL;
        if (quote) {
            text[used++] = '"';
        }
        size_t slashes = 0;
        for (const char *c = arg; *c != 0; c++) {
            if (*c == '\\') {
                slashes++;
                text[used++] = '\\';
                continue;
            }
            if (*c == '"') {
                for (size_t k = 0; k <= slashes; k++) {
                    text[used++] = '\\'; /* the backslashes before a quote double, and the quote is escaped */
                }
            }
            slashes = 0;
            text[used++] = *c;
        }
        if (quote) {
            for (size_t k = 0; k < slashes; k++) {
                text[used++] = '\\'; /* the backslashes before the closing quote double */
            }
            text[used++] = '"';
        }
    }
    text[used] = 0;
    WCHAR *wide = wide_of(text, used);
    free(text);
    return wide;
}

/* The environment block: this process's variables with `overrides` replacing or adding their names, as UTF-16
 * `NAME=value` strings ended by an empty string. */
static WCHAR *environment_block(char *const *overrides) {
    WCHAR *inherited = GetEnvironmentStringsW();
    if (inherited == NULL) {
        return NULL;
    }
    size_t units = 1, count = 0;
    for (const WCHAR *c = inherited; *c != 0; c += wcslen(c) + 1) {
        units += wcslen(c) + 1;
    }
    while (overrides != NULL && overrides[count] != NULL) {
        units += strlen(overrides[count++]) + 1;
    }
    WCHAR *block = malloc(units * sizeof *block);
    WCHAR **names = count == 0 ? NULL : calloc(count, sizeof *names);
    bool ok = block != NULL && (count == 0 || names != NULL);
    size_t used = 0;
    for (size_t k = 0; ok && k < count; k++) {
        names[k] = wide_of(overrides[k], strlen(overrides[k]));
        ok = names[k] != NULL;
    }
    for (const WCHAR *c = inherited; ok && *c != 0; c += wcslen(c) + 1) {
        const WCHAR *equals = wcschr(c + 1, L'=');
        const size_t name = equals != NULL ? (size_t)(equals - c) : wcslen(c);
        bool replaced = false;
        for (size_t k = 0; k < count && !replaced; k++) {
            replaced = _wcsnicmp(names[k], c, name) == 0 && names[k][name] == L'=';
        }
        if (!replaced) {
            const size_t length = wcslen(c) + 1;
            memcpy(block + used, c, length * sizeof *c);
            used += length;
        }
    }
    for (size_t k = 0; ok && k < count; k++) {
        const size_t length = wcslen(names[k]) + 1;
        memcpy(block + used, names[k], length * sizeof *block);
        used += length;
    }
    for (size_t k = 0; names != NULL && k < count; k++) {
        free(names[k]);
    }
    free(names);
    (void)FreeEnvironmentStringsW(inherited);
    if (!ok) {
        free(block);
        return NULL;
    }
    block[used] = 0;
    return block;
}

MsSysError ms_sys_process_run(char *const *argv, char *const *env, const char *cwd, bool merge, MsSysRun *run) {
    *run = (MsSysRun){.code = -1};
    WCHAR *line = command_line(argv);
    WCHAR *block = environment_block(env);
    WCHAR *directory = cwd != NULL ? wide_of(cwd, strlen(cwd)) : NULL;
    if (line == NULL || block == NULL || (cwd != NULL && directory == NULL)) {
        free(line);
        free(block);
        free(directory);
        return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    }
    SECURITY_ATTRIBUTES inherit = {.nLength = sizeof inherit, .bInheritHandle = TRUE};
    HANDLE out_read = NULL, out_write = NULL, err_read = NULL, err_write = NULL;
    HANDLE input = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &inherit, OPEN_EXISTING, 0, NULL);
    DWORD failure = input == INVALID_HANDLE_VALUE ? GetLastError() : 0;
    if (failure == 0 && !CreatePipe(&out_read, &out_write, &inherit, 0)) {
        failure = GetLastError();
    }
    if (failure == 0 && !merge && !CreatePipe(&err_read, &err_write, &inherit, 0)) {
        failure = GetLastError();
    }
    PROCESS_INFORMATION process = {0};
    if (failure == 0) {
        /* The read ends stay in this process. */
        (void)SetHandleInformation(out_read, HANDLE_FLAG_INHERIT, 0);
        if (err_read != NULL) {
            (void)SetHandleInformation(err_read, HANDLE_FLAG_INHERIT, 0);
        }
        STARTUPINFOW startup = {.cb = sizeof startup,
                                .dwFlags = STARTF_USESTDHANDLES,
                                .hStdInput = input,
                                .hStdOutput = out_write,
                                .hStdError = merge ? out_write : err_write};
        if (!CreateProcessW(NULL, line, NULL, NULL, TRUE, CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW, block, directory,
                            &startup, &process)) {
            failure = GetLastError();
        }
    }
    free(line);
    free(block);
    free(directory);
    if (input != INVALID_HANDLE_VALUE) {
        (void)CloseHandle(input);
    }
    if (out_write != NULL) {
        (void)CloseHandle(out_write);
    }
    if (err_write != NULL) {
        (void)CloseHandle(err_write);
    }
    if (failure != 0) {
        if (out_read != NULL) {
            (void)CloseHandle(out_read);
        }
        if (err_read != NULL) {
            (void)CloseHandle(err_read);
        }
        return (MsSysError)failure;
    }
    Sink out = {.pipe = out_read}, err = {.pipe = err_read};
    HANDLE helper = err_read != NULL ? CreateThread(NULL, 0, drain, &err, 0, NULL) : NULL;
    if (err_read != NULL && helper == NULL) {
        failure = GetLastError();
        (void)TerminateProcess(process.hProcess, 1);
    } else {
        (void)drain(&out);
    }
    if (helper != NULL) {
        (void)WaitForSingleObject(helper, INFINITE);
        (void)CloseHandle(helper);
    }
    DWORD code = 1;
    (void)WaitForSingleObject(process.hProcess, INFINITE);
    (void)GetExitCodeProcess(process.hProcess, &code);
    (void)CloseHandle(process.hProcess);
    (void)CloseHandle(process.hThread);
    (void)CloseHandle(out_read);
    if (err_read != NULL) {
        (void)CloseHandle(err_read);
    }
    if (failure == 0) {
        failure = out.failure != 0 ? out.failure : err.failure;
    }
    if (failure != 0) {
        free(out.data);
        free(err.data);
        return (MsSysError)failure;
    }
    run->code = (int32_t)code;
    run->out = out.data != NULL ? out.data : calloc(1, 1);
    run->out_length = out.length;
    if (!merge) {
        run->err = err.data != NULL ? err.data : calloc(1, 1);
        run->err_length = err.length;
    }
    return 0;
}

void ms_sys_process_run_free(MsSysRun *run) {
    free(run->out);
    free(run->err);
    *run = (MsSysRun){.code = -1};
}
