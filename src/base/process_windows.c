/* Running a child program on Windows (see process.h). Arguments are quoted for the Microsoft C runtime. */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define NOGDI
#define NOUSER
#include <windows.h>

#include "base/ostext.h"
#include "base/process.h"

static bool needs_quotes(MsSpan argument) {
  if (argument.len == 0) {
    return true;
  }
  for (size_t index = 0; index < argument.len; index++) {
    uint8_t byte = argument.ptr[index];
    if (byte == ' ' || byte == '\t' || byte == '\n' || byte == '\v' || byte == '"') {
      return true;
    }
  }
  return false;
}

static void append_repeated(MsStrBuild *out, uint8_t byte, size_t count) {
  for (size_t index = 0; index < count; index++) {
    ms_strbuild_append_byte(out, byte);
  }
}

/* One argument as the C runtime reads it back: backslashes before a quote are doubled. */
static void append_quoted(MsStrBuild *line, MsSpan argument) {
  if (!needs_quotes(argument)) {
    ms_strbuild_append(line, argument);
    return;
  }
  ms_strbuild_append_byte(line, '"');
  size_t backslashes = 0;
  for (size_t index = 0; index < argument.len; index++) {
    uint8_t byte = argument.ptr[index];
    if (byte == '\\') {
      backslashes++;
      continue;
    }
    append_repeated(line, '\\', byte == '"' ? backslashes * 2 + 1 : backslashes);
    backslashes = 0;
    ms_strbuild_append_byte(line, byte);
  }
  append_repeated(line, '\\', backslashes * 2);
  ms_strbuild_append_byte(line, '"');
}

static void append_win32_error(DWORD code, MsStrBuild *out) {
  char message[256] = "";
  DWORD length = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, code, 0,
                                message, sizeof message, NULL);
  while (length > 0 && (message[length - 1] == '\r' || message[length - 1] == '\n' || message[length - 1] == ' ')) {
    length--;
  }
  if (length == 0) {
    ms_strbuild_append_text(out, "error ");
    ms_strbuild_append_u64(out, code);
    return;
  }
  ms_strbuild_append(out, ms_span_of((const uint8_t *)message, length));
}

static MsOsWide command_line(const MsProcessSpec *spec) {
  MsStrBuild line = ms_strbuild_new();
  for (size_t index = 0; index < spec->argc; index++) {
    if (index > 0) {
      ms_strbuild_append_byte(&line, ' ');
    }
    append_quoted(&line, spec->argv[index]);
  }
  MsString text = ms_strbuild_finish(&line);
  MsOsWide wide = ms_os_wide_new(ms_string_span(&text), false);
  ms_string_release(&text);
  return wide;
}

static bool launch(const MsProcessSpec *spec, HANDLE input, HANDLE output, int *exit_status, MsStrBuild *error) {
  MsOsWide line = command_line(spec);
  MsOsWide directory = ms_os_wide_new(spec->directory, true);
  STARTUPINFOW startup = {.cb = sizeof startup,
                          .dwFlags = STARTF_USESTDHANDLES,
                          .hStdInput = input,
                          .hStdOutput = output,
                          .hStdError = output};
  PROCESS_INFORMATION process = {0};
  bool started = line.ptr != NULL && directory.ptr != NULL &&
                 CreateProcessW(NULL, (WCHAR *)line.ptr, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL,
                                spec->directory.len == 0 ? NULL : (const WCHAR *)directory.ptr, &startup, &process);
  if (!started) {
    append_win32_error(GetLastError(), error);
  } else {
    DWORD code = 1;
    (void)WaitForSingleObject(process.hProcess, INFINITE);
    started = GetExitCodeProcess(process.hProcess, &code) != 0;
    *exit_status = (int)code;
    (void)CloseHandle(process.hProcess);
    (void)CloseHandle(process.hThread);
  }
  ms_os_wide_free(&line);
  ms_os_wide_free(&directory);
  return started;
}

bool ms_process_run(const MsProcessSpec *spec, int *exit_status, MsStrBuild *error) {
  MsOsWide log = ms_os_wide_new(spec->log_path, true);
  SECURITY_ATTRIBUTES inherit = {.nLength = sizeof inherit, .lpSecurityDescriptor = NULL, .bInheritHandle = TRUE};
  HANDLE output = log.ptr == NULL ? INVALID_HANDLE_VALUE
                                  : CreateFileW((const WCHAR *)log.ptr, GENERIC_WRITE, FILE_SHARE_READ, &inherit,
                                                CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  HANDLE input = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &inherit, OPEN_EXISTING,
                             FILE_ATTRIBUTE_NORMAL, NULL);
  bool ok = false;
  if (output == INVALID_HANDLE_VALUE || input == INVALID_HANDLE_VALUE) {
    ms_strbuild_append_text(error, "cannot prepare the command");
  } else {
    ok = launch(spec, input, output, exit_status, error);
  }
  if (output != INVALID_HANDLE_VALUE) {
    (void)CloseHandle(output);
  }
  if (input != INVALID_HANDLE_VALUE) {
    (void)CloseHandle(input);
  }
  ms_os_wide_free(&log);
  return ok;
}

bool ms_process_find(MsSpan name) {
  MsOsWide wide = ms_os_wide_new(name, false);
  bool found = wide.ptr != NULL && SearchPathW(NULL, (const WCHAR *)wide.ptr, L".exe", 0, NULL, NULL) != 0;
  ms_os_wide_free(&wide);
  return found;
}

#endif
