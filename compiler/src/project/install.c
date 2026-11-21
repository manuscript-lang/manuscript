/* `ms install`: the git remote the resolver talks to, the download into the package cache, and the install
 * procedure. Port of crates/ms-cli/src/fetch.rs. See ms/packages.h. */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/packages.h"
#include "ms_rt/sys_process.h"
#include "project/host.h"

#define COMMIT_DIGITS 40

/* ---- operating-system errors, spelled as Rust's io::Error does ---- */

static const char *install_os_error(MsArena *a, MsSysError code) {
    char message[256];
    (void)ms_sys_fs_error_text(code, message, sizeof message);
    return ms_arena_fmt(a, "%s (os error %d)", message, code).ptr;
}

/* Drops the result of a best-effort call. */
static void install_ignore(MsSysError code) { (void)code; }

/* A name that differs between processes and between calls, for temporary paths. */
static unsigned long install_unique(void) { return (unsigned long)ms_sys_fs_random(); }

/* Writes `length` bytes to `path`, replacing it. */
static MsSysError install_write_file(const char *path, const char *bytes, size_t length) {
    MsSysFd fd;
    MsSysError failure = ms_sys_fs_open(path, MS_SYS_O_WRITE | MS_SYS_O_CREATE | MS_SYS_O_TRUNCATE, 0666, &fd);
    if (failure != 0) {
        return failure;
    }
    size_t done = 0;
    while (failure == 0 && done < length) {
        size_t count = 0;
        failure = ms_sys_fs_write(fd, (const uint8_t *)bytes + done, length - done, &count);
        done += count;
    }
    const MsSysError closed = ms_sys_fs_close(fd);
    return failure != 0 ? failure : closed;
}

/* ---- directories ---- */

/* `mkdir -p`. */
static bool install_make_dirs(MsArena *a, const char *path, const char **error) {
    char *copy = ms_arena_strndup(a, path, strlen(path));
    for (char *at = copy + 1; ; at++) {
        const bool last = *at == 0;
        if (*at == '/' || last) {
            *at = 0;
            const MsSysError failure = ms_sys_fs_mkdir(copy, 0777);
            if (failure != 0 && !host_exists_error(failure)) {
                *error = ms_arena_fmt(a, "create %s: %s", path, install_os_error(a, failure)).ptr;
                return false;
            }
            if (last) {
                return true;
            }
            *at = '/';
        }
    }
}

/* Removes a tree even when git made some of it read-only. A path that is already gone is not a failure. */
bool ms_remove_all(MsArena *a, const char *path, const char **error) {
    MsSysStat info;
    MsSysError failure = ms_sys_fs_stat(path, false, &info);
    if (failure != 0) {
        if (host_missing(failure)) {
            return true;
        }
        *error = ms_arena_fmt(a, "remove %s: %s", path, install_os_error(a, failure)).ptr;
        return false;
    }
    if (host_is_dir(&info)) {
        install_ignore(ms_sys_fs_chmod(path, 0755));
        const char *const *names;
        uint32_t count;
        MsProjectError listing = {0};
        if (!ms_path_list_dir(a, path, "remove", &names, &count, &listing)) {
            *error = ms_project_error_text(a, &listing);
            return false;
        }
        for (uint32_t i = 0; i < count; i++) {
            if (!ms_remove_all(a, MS_PATH_JOIN(a, path, names[i]), error)) {
                return false;
            }
        }
        failure = ms_sys_fs_rmdir(path);
        if (failure != 0) {
            *error = ms_arena_fmt(a, "remove %s: %s", path, install_os_error(a, failure)).ptr;
            return false;
        }
        return true;
    }
    failure = ms_sys_fs_unlink(path);
    if (failure != 0) {
        *error = ms_arena_fmt(a, "remove %s: %s", path, install_os_error(a, failure)).ptr;
        return false;
    }
    return true;
}

/* Clears the write bits of every file and leaves directories readable and searchable only. */
static void install_read_only(MsArena *a, const char *dir) {
    const char *const *names;
    uint32_t count;
    MsProjectError failure = {0};
    if (ms_path_list_dir(a, dir, "read directory", &names, &count, &failure)) {
        for (uint32_t i = 0; i < count; i++) {
            const char *path = MS_PATH_JOIN(a, dir, names[i]);
            MsSysStat info;
            if (ms_sys_fs_stat(path, false, &info) != 0) {
                continue;
            }
            if (host_is_dir(&info)) {
                install_read_only(a, path);
            } else {
                install_ignore(ms_sys_fs_chmod(path, info.mode & 07555));
            }
        }
    }
    install_ignore(ms_sys_fs_chmod(dir, 0555));
}

/* ---- git ---- */

typedef struct Remote {
    MsArena *arena;
    const char *cache;
    MsBuf records;          /* CopyRecord */
} Remote;

/* The text of `text` without the `user:password@` of any URL in it, so a token in a dependency URL is not echoed
 * into terminal logs and CI output by an error message. */
static const char *install_redact(MsArena *a, const char *text) {
    MsBuf out = {0};
    const char *rest = text;
    const char *scheme;
    while ((scheme = strstr(rest, "://")) != NULL) {
        const char *authority = scheme + 3;
        ms_buf_put(&out, rest, (size_t)(authority - rest));
        size_t end = 0;
        while (authority[end] != 0 && !isspace((unsigned char)authority[end]) && authority[end] != '/' && authority[end] != '\'' && authority[end] != '"') {
            end++;
        }
        const char *host = authority;
        for (size_t i = 0; i < end; i++) {
            if (authority[i] == '@') {
                host = authority + i + 1; /* the last one: a password may hold an @ */
            }
        }
        ms_buf_put(&out, host, (size_t)(authority + end - host));
        rest = authority + end;
    }
    ms_buf_puts(&out, rest);
    const char *result = ms_arena_strndup(a, out.data == NULL ? "" : out.data, out.len);
    ms_buf_free(&out);
    return result;
}

static const char *install_trim(MsArena *a, const char *text, size_t length) {
    while (length > 0 && isspace((unsigned char)text[length - 1])) {
        length--;
    }
    while (length > 0 && isspace((unsigned char)text[0])) {
        text++;
        length--;
    }
    return ms_arena_strndup(a, text, length);
}

/* The environment git runs in: no prompts, no localisation, and only the transports a package may use. */
static char *const *install_git_environment(MsArena *a, const char *protocols) {
    char **env = MS_NEW_N(a, char *, 4);
    env[0] = ms_arena_strndup(a, "GIT_TERMINAL_PROMPT=0", 21);
    env[1] = ms_arena_strndup(a, "LC_ALL=C", 8);
    const MsStr allow = ms_arena_fmt(a, "GIT_ALLOW_PROTOCOL=%s", protocols);
    env[2] = ms_arena_strndup(a, allow.ptr, allow.len);
    env[3] = NULL;
    return env;
}

/* Runs `git [-C dir] args...` (args end with NULL) and returns its standard output. A failure is `git <args>
 * failed: <stderr>` with credentials removed. */
static bool install_git(MsArena *a, const char *dir, const char *protocols, const char *const *args, const char **output,
                        const char **error) {
    static char git[] = "git";
    static char *const options[] = {git, "-c", "core.autocrlf=false", "-c", "core.safecrlf=false", "-c",
                                    "advice.detachedHead=false",
                                    /* A server that stops sending must fail the install, not hang it. */
                                    "-c", "http.lowSpeedLimit=1000", "-c", "http.lowSpeedTime=30"};
    MsBuf argv = {0};
    for (size_t i = 0; i < sizeof options / sizeof options[0]; i++) {
        MS_VEC_PUSH(argv, char *, options[i]);
    }
    if (dir != NULL) {
        MS_VEC_PUSH(argv, char *, ms_arena_strndup(a, "-C", 2));
        MS_VEC_PUSH(argv, char *, ms_arena_strndup(a, dir, strlen(dir)));
    }
    MsBuf joined = {0};
    for (const char *const *arg = args; *arg != NULL; arg++) {
        MS_VEC_PUSH(argv, char *, ms_arena_strndup(a, *arg, strlen(*arg)));
        ms_buf_puts(&joined, arg == args ? "" : " ");
        ms_buf_puts(&joined, *arg);
    }
    MS_VEC_PUSH(argv, char *, NULL);

    MsSysRun run;
    const MsSysError failure = ms_sys_process_run((char *const *)ms_buf_items(&argv), install_git_environment(a, protocols), NULL, false, &run);
    bool ok = false;
    if (failure != 0) {
        *error = ms_arena_fmt(a, "cannot run git (%s); install git and put it on PATH", install_os_error(a, failure)).ptr;
    } else {
        ok = run.code == 0;
        if (ok) {
            *output = ms_arena_strndup(a, run.out, run.out_length);
        } else {
            *error = ms_arena_fmt(a, "git %s failed: %s", install_redact(a, ms_arena_strndup(a, joined.data == NULL ? "" : joined.data, joined.len)),
                                  install_redact(a, install_trim(a, run.err, run.err_length))).ptr;
        }
        ms_sys_process_run_free(&run);
    }
    ms_buf_free(&argv);
    ms_buf_free(&joined);
    return ok;
}

#define INSTALL_GIT(a, dir, protocols, output, error, ...) \
    install_git((a), (dir), (protocols), (const char *const[]){__VA_ARGS__, NULL}, (output), (error))

/* ---- portability and validity of a download ---- */

/* Whether the first `length` bytes of `left` and `right` are equal, ignoring ASCII case. */
static bool install_same_text(const char *left, const char *right, size_t length) {
    for (size_t i = 0; i < length; i++) {
        if (tolower((unsigned char)left[i]) != tolower((unsigned char)right[i])) {
            return false;
        }
    }
    return true;
}

/* Whether Windows can create a file or directory called `name`. */
static bool install_portable_name(const char *name) {
    static const char *const reserved[] = {"con",  "prn",  "aux",  "nul",  "com1", "com2", "com3", "com4",
                                           "com5", "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3",
                                           "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"};
    const size_t length = strlen(name);
    if (length > 0 && (name[length - 1] == '.' || name[length - 1] == ' ')) {
        return false;
    }
    for (const char *c = name; *c != 0; c++) {
        if ((unsigned char)*c < 0x20 || *c == 0x7f || strchr("<>:\"\\|?*", *c) != NULL) {
            return false;
        }
    }
    const size_t stem_length = strcspn(name, ".");
    for (size_t i = 0; i < sizeof reserved / sizeof reserved[0]; i++) {
        if (strlen(reserved[i]) == stem_length && install_same_text(name, reserved[i], stem_length)) {
            return false;
        }
    }
    return true;
}

static const char *install_lower(MsArena *a, const char *text) {
    char *copy = ms_arena_strndup(a, text, strlen(text));
    for (char *c = copy; *c != 0; c++) {
        *c = (char)tolower((unsigned char)*c);
    }
    return copy;
}

/* A package is judged from git's own record of the checkout, because the hash is taken from the directory and must
 * come out the same on Linux, macOS and Windows. Three things make a checkout differ by platform, so each is
 * rejected on every platform: a symbolic link, two paths that differ only by letter case, and a name Windows cannot
 * create. */
static bool install_reject_unportable(MsArena *a, const char *key, const char *directory, const char *protocols, const char **error) {
    const char *listing;
    if (!INSTALL_GIT(a, directory, protocols, &listing, error, "ls-files", "-z", "--stage")) {
        return false;
    }
    MsBuf lowered = {0}; /* const char *: the lower-cased paths seen so far, then their originals */
    MsBuf originals = {0};
    bool ok = true;
    for (const char *entry = listing; ok && *entry != 0; entry += strlen(entry) + 1) {
        const char *tab = strchr(entry, '\t');
        if (tab == NULL) {
            continue;
        }
        const char *path = tab + 1;
        if (strncmp(entry, "120000 ", 7) == 0) {
            *error = ms_arena_fmt(a, "package %s: package contains the symbolic link %s; a package holds regular files only", key, path).ptr;
            ok = false;
            break;
        }
        for (const char *part = path; ok && *part != 0;) {
            const size_t length = strcspn(part, "/");
            const char *name = ms_arena_strndup(a, part, length);
            if (!install_portable_name(name)) {
                *error = ms_arena_fmt(a, "package %s: %s has the name \"%s\", which Windows cannot create; rename it", key, path, name).ptr;
                ok = false;
            }
            part += length + (part[length] == '/' ? 1 : 0);
        }
        const char *folded = install_lower(a, path);
        for (size_t i = 0; ok && i < MS_VEC_LEN(lowered, const char *); i++) {
            if (strcmp(MS_VEC_AT(lowered, const char *, i), folded) == 0) {
                *error = ms_arena_fmt(a, "package %s: %s and %s differ only by letter case, so one overwrites the other on macOS and Windows; rename one",
                                      key, MS_VEC_AT(originals, const char *, i), path).ptr;
                ok = false;
            }
        }
        MS_VEC_PUSH(lowered, const char *, folded);
        MS_VEC_PUSH(originals, const char *, path);
    }
    ms_buf_free(&lowered);
    ms_buf_free(&originals);
    return ok;
}

/* `text` with every `needle` removed. */
static const char *install_strip(MsArena *a, const char *text, const char *needle) {
    MsBuf out = {0};
    const size_t length = strlen(needle);
    const char *at;
    while (length > 0 && (at = strstr(text, needle)) != NULL) {
        ms_buf_put(&out, text, (size_t)(at - text));
        text = at + length;
    }
    ms_buf_puts(&out, text);
    const char *result = ms_arena_strndup(a, out.data == NULL ? "" : out.data, out.len);
    ms_buf_free(&out);
    return result;
}

/* A package is a library with a manifest, no entry, no embedded files and no top-level `@` directory (which would
 * look like a nested package in diagnostics). The checker enforces everything about its source. */
static bool install_validate(MsArena *a, const char *key, const char *dir, const char **error) {
    const char *manifest = MS_PATH_JOIN(a, dir, "ms.toml");
    MsSysStat info;
    if (ms_sys_fs_stat(manifest, true, &info) != 0 || !host_is_reg(&info)) {
        *error = ms_arena_fmt(a, "package %s has no ms.toml at its root", key).ptr;
        return false;
    }
    MsProject package;
    MsProjectError failure = {0};
    if (!ms_project_read(a, manifest, &package, &failure)) {
        /* The download sits in a temporary directory; name paths from the package root. */
        const char *message = install_strip(a, ms_project_error_text(a, &failure), ms_arena_fmt(a, "%s/", dir).ptr);
        *error = ms_arena_fmt(a, "package %s: %s", key, message).ptr;
        return false;
    }
    if (package.entry[0] != 0) {
        *error = ms_arena_fmt(a, "package %s has an entry; a package is a library, so remove entry", key).ptr;
        return false;
    }
    if (package.embed_count != 0) {
        *error = ms_arena_fmt(a, "package %s declares [embed]; a package holds source only", key).ptr;
        return false;
    }
    const char *const *names;
    uint32_t count;
    if (!ms_path_list_dir(a, dir, "read", &names, &count, &failure)) {
        *error = ms_project_error_text(a, &failure);
        return false;
    }
    for (uint32_t i = 0; i < count; i++) {
        if (names[i][0] == '@') {
            *error = ms_arena_fmt(a, "package %s has a top-level \"%s\"; rename it, names starting with @ are reserved for packages", key, names[i]).ptr;
            return false;
        }
    }
    return true;
}

/* ---- download ---- */

typedef struct Download {
    MsLockEntry entry;
    bool was_cached; /* the cache already held this content */
} Download;

static const char *install_protocols(bool nested) {
    return nested ? "https" : "https:file";
}

static bool install_is_commit(const char *text) {
    return ms_is_hex(text, strlen(text)) && strlen(text) == COMMIT_DIGITS;
}

/* Moves the verified download into the cache beside its index. The index goes first and atomically, so a directory
 * that exists is always complete beside its index when another install runs. */
static bool install_store(MsArena *a, const char *temporary, const char *root, const char *hash, MsStr index, bool *was_cached, const char **error) {
    const char *destination = MS_PATH_JOIN(a, root, hash);
    *was_cached = ms_package_cached_intact(a, root, hash);
    if (*was_cached) {
        return true;
    }
    const char *index_file = MS_PATH_JOIN(a, root, ms_arena_fmt(a, "%s.index", hash).ptr);
    const char *staged = MS_PATH_JOIN(a, root, ms_arena_fmt(a, ".tmp-%lu.index", install_unique()).ptr);
    MsSysError failure = install_write_file(staged, index.ptr, index.len);
    if (failure != 0) {
        *error = ms_arena_fmt(a, "write %s: %s", staged, install_os_error(a, failure)).ptr;
        return false;
    }
    failure = ms_sys_fs_rename(staged, index_file);
    if (failure != 0) {
        *error = ms_arena_fmt(a, "write %s: %s", index_file, install_os_error(a, failure)).ptr;
        return false;
    }
    MsSysStat info;
    if (ms_sys_fs_stat(destination, false, &info) == 0 && !ms_package_cached_intact(a, root, hash) && !ms_remove_all(a, destination, error)) {
        return false;
    }
    failure = ms_sys_fs_rename(temporary, destination);
    if (failure != 0 && !ms_package_cached_intact(a, root, hash)) {
        *error = ms_arena_fmt(a, "store %s: %s", destination, install_os_error(a, failure)).ptr;
        return false;
    }
    install_read_only(a, destination);
    return true;
}

/* Fetches `reference` of `url` into `temporary` (a tag with `tag:tag`, a commit or the locked revision by itself)
 * and returns the commit it resolved to. */
static bool install_fetch_commit(MsArena *a, const char *key, const char *url, const char *reference, const MsLockEntry *locked,
                                 const char *temporary, const char *protocols, const char **commit, const char **error) {
    const char *ignored;
    if (!INSTALL_GIT(a, temporary, protocols, &ignored, error, "init", "--quiet") ||
        !INSTALL_GIT(a, temporary, protocols, &ignored, error, "remote", "add", "--", "origin", url)) {
        return false;
    }
    const bool by_commit = locked != NULL || install_is_commit(reference);
    const char *wanted = locked != NULL ? locked->revision : reference;
    const char *tag = ms_arena_fmt(a, "refs/tags/%s", reference).ptr;
    const char *refspec = by_commit ? wanted : ms_arena_fmt(a, "%s:%s", tag, tag).ptr;
    const char *failure;
    if (!INSTALL_GIT(a, temporary, protocols, &ignored, &failure, "fetch", "--quiet", "--depth", "1", "--", "origin", refspec)) {
        /* Only a missing ref means a wrong tag; a refused, unreachable or stalled server is reported as git said it. */
        const bool wrong_tag = !by_commit && strstr(failure, "couldn't find remote ref") != NULL;
        *error = wrong_tag ? ms_arena_fmt(a, "package %s: %s is not a tag of %s: %s", key, reference, url, failure).ptr
                           : ms_arena_fmt(a, "package %s: %s", key, failure).ptr;
        return false;
    }
    const char *revision = by_commit ? "FETCH_HEAD" : ms_arena_fmt(a, "refs/tags/%s^{commit}", reference).ptr;
    const char *printed;
    if (!INSTALL_GIT(a, temporary, protocols, &printed, error, "rev-parse", "--verify", revision)) {
        return false;
    }
    *commit = install_trim(a, printed, strlen(printed));
    return INSTALL_GIT(a, temporary, protocols, &ignored, error, "checkout", "--quiet", "--force", *commit, "--");
}

static bool install_download_into(MsArena *a, const char *key, const char *url, const char *reference,
                                  const MsLockEntry *locked, const char *temporary, const char *root, const char *protocols,
                                  Download *out, const char **error) {
    const char *commit;
    if (!install_fetch_commit(a, key, url, reference, locked, temporary, protocols, &commit, error) ||
        !install_reject_unportable(a, key, temporary, protocols, error) ||
        !ms_remove_all(a, MS_PATH_JOIN(a, temporary, ".git"), error)) {
        return false;
    }
    MsStr index;
    MsProjectError failure = {0};
    if (!ms_package_index(a, temporary, &index, &failure)) {
        *error = ms_arena_fmt(a, "package %s: %s", key, ms_project_error_text(a, &failure)).ptr;
        return false;
    }
    const char *hash = ms_package_hash(a, index);
    if (locked != NULL && strcmp(locked->sha256, hash) != 0) {
        *error = ms_arena_fmt(a, "package %s at %s no longer matches ms.lock (locked %s, got %s); the source changed, so review it and run `ms install --update %s` if you trust it",
                              key, locked->revision, locked->sha256, hash, key).ptr;
        return false;
    }
    if (!install_validate(a, key, temporary, error) || !install_store(a, temporary, root, hash, index, &out->was_cached, error)) {
        return false;
    }
    out->entry = (MsLockEntry){.key = "", .spec = "", .revision = commit, .sha256 = hash};
    return true;
}

/* Downloads `spec` into the cache. With a lock entry it fetches exactly that revision and checks its hash; otherwise
 * it resolves the tag. */
static bool install_download(Remote *r, MsArena *a, const char *url, const char *spec, const MsLockEntry *locked, bool nested,
                             Download *out, const char **error) {
    const char *reference = strchr(spec, '#');
    if (reference == NULL) {
        *error = "dependency needs url#tag";
        return false;
    }
    reference++;
    const char *root = r->cache;
    const char *temporary = MS_PATH_JOIN(a, root, ms_arena_fmt(a, ".tmp-%lu", install_unique()).ptr);
    const char *ignored;
    bool ok = install_make_dirs(a, root, error) && ms_remove_all(a, temporary, error) && install_make_dirs(a, temporary, error) &&
              install_download_into(a, url, url, ms_arena_strndup(a, reference, strlen(reference)), locked, temporary, root,
                                    install_protocols(nested), out, error);
    const bool removed = ms_remove_all(a, temporary, &ignored); /* a leftover is replaced by the next download */
    (void)removed;
    if (ok) {
        out->entry.spec = spec;
    }
    return ok;
}

/* ---- the remote the resolver sees ---- */

typedef struct CopyRecord {
    const char *id;
    MsInstallState state;
    const char *effects;
} CopyRecord;

static bool remote_tags(void *user, MsArena *a, const char *url, const char *const **tags, uint32_t *count, const char **error) {
    (void)user;
    const char *listing;
    const char *protocols = install_protocols(strncmp(url, "https://", 8) == 0 ? true : false);
    if (!INSTALL_GIT(a, NULL, protocols, &listing, error, "ls-remote", "--tags", "--refs", "--", url)) {
        return false;
    }
    MsBuf names = {0};
    static const char marker[] = "\trefs/tags/";
    for (const char *line = listing; *line != 0;) {
        const size_t length = strcspn(line, "\n");
        const char *at = strstr(line, marker);
        if (at != NULL && at < line + length) {
            const char *tag = at + sizeof marker - 1;
            MS_VEC_PUSH(names, const char *, ms_arena_strndup(a, tag, (size_t)(line + length - tag)));
        }
        line += length + (line[length] == '\n' ? 1 : 0);
    }
    *count = (uint32_t)MS_VEC_LEN(names, const char *);
    const char **result = MS_NEW_N(a, const char *, *count + 1);
    for (uint32_t i = 0; i < *count; i++) {
        result[i] = MS_VEC_AT(names, const char *, i);
    }
    ms_buf_free(&names);
    *tags = result;
    return true;
}

/* The effects `[project] effects` lists, as `ms install` prints them. */
static const char *remote_effects(MsArena *a, const MsProject *project) {
    if (project->effect_count == 0) {
        return "none";
    }
    MsBuf text = {0};
    for (uint32_t i = 0; i < project->effect_count; i++) {
        ms_buf_puts(&text, i == 0 ? "" : " ");
        ms_buf_puts(&text, project->effects[i]);
    }
    const char *result = ms_arena_strndup(a, text.data, text.len);
    ms_buf_free(&text);
    return result;
}

static void remote_record(Remote *r, const char *id, MsInstallState state, const char *effects) {
    for (size_t i = 0; i < MS_VEC_LEN(r->records, CopyRecord); i++) {
        CopyRecord *seen = &MS_VEC_AT(r->records, CopyRecord, i);
        if (strcmp(seen->id, id) == 0) {
            if (state == MS_INSTALL_FETCHED || seen->state != MS_INSTALL_FETCHED) {
                seen->state = state;
            }
            seen->effects = effects;
            return;
        }
    }
    MS_VEC_PUSH(r->records, CopyRecord, ((CopyRecord){id, state, effects}));
}

static bool remote_fetch(void *user, MsArena *a, const char *url, const char *reference, const MsLockEntry *locked, bool nested,
                         MsFetched *out, const char **error) {
    Remote *r = user;
    const char *spec = ms_arena_fmt(a, "%s#%s", url, reference).ptr;
    Download download = {0};
    MsInstallState state = MS_INSTALL_KEPT;
    if (locked != NULL && ms_package_cached_intact(a, r->cache, locked->sha256)) {
        download.entry = *locked;
    } else {
        if (!install_download(r, a, url, spec, locked, nested, &download, error)) {
            return false;
        }
        state = download.was_cached ? MS_INSTALL_CACHED : MS_INSTALL_FETCHED;
    }
    MsProject package;
    MsProjectError failure = {0};
    const char *manifest = MS_PATH_JOIN(a, r->cache, download.entry.sha256, "ms.toml");
    if (!ms_project_read(a, manifest, &package, &failure)) {
        *error = ms_arena_fmt(a, "package %s: %s", url, ms_project_error_text(a, &failure)).ptr;
        return false;
    }
    remote_record(r, ms_copy_id(r->arena, url, reference), state, remote_effects(r->arena, &package));
    out->entry = download.entry;
    out->manifest = (MsPackageManifest){.deps = package.dependencies, .ndeps = package.dependency_count,
                                        .has_version = package.has_version, .version = package.version};
    return true;
}

/* ---- the install procedure ---- */

/* Whether `directory` or an ancestor holds a workspace root. */
static bool install_in_workspace(MsArena *a, const char *directory) {
    for (const char *dir = directory;;) {
        const char *candidate = MS_PATH_JOIN(a, dir, "ms.toml");
        MsProject project;
        MsProjectError failure = {0};
        if (ms_sys_fs_access(candidate, 0) == 0) {
            if (ms_project_read(a, candidate, &project, &failure) && project.is_workspace) {
                return true;
            }
        }
        const char *parent = ms_path_dir(a, dir);
        if (strcmp(parent, dir) == 0) {
            return false;
        }
        dir = parent;
    }
}

static int install_copy_order(const void *left, const void *right) {
    return strcmp(((const MsInstalledCopy *)left)->copy.id, ((const MsInstalledCopy *)right)->copy.id);
}

static const char *install_root_name(const MsResolved *resolved, const char *id) {
    const char *name = id;
    for (uint32_t i = 0; i < resolved->nroots; i++) {
        if (strcmp(resolved->roots[i].id, id) == 0) {
            name = resolved->roots[i].alias; /* the last alias in order, as the Rust map keeps it */
        }
    }
    return name;
}

/* Writes ms.lock when its text changed, and removes it when there is nothing to pin. */
static bool install_write_lock(MsArena *a, const char *root, const MsResolved *resolved, const MsInstallOptions *options,
                               MsProjectError *err) {
    const char *path = MS_PATH_JOIN(a, root, "ms.lock");
    MsLockEntry *entries = ms_resolved_lock(a, resolved);
    const bool empty = resolved->ncopies == 0;
    const char *text = empty ? NULL : ms_lock_text(a, entries, resolved->ncopies);
    size_t length = 0;
    MsProjectError read_error = {0};
    const char *current = ms_project_read_file(a, path, &length, &read_error);
    const bool same = empty ? current == NULL : current != NULL && strcmp(current, text) == 0;
    if (same || options->frozen) {
        return true;
    }
    if (options->locked) {
        ms_project_error_message(err, "ms.lock needs to be updated but --locked was passed; run ms install to update it");
        return false;
    }
    if (empty) {
        install_ignore(ms_sys_fs_unlink(path));
        return true;
    }
    const MsSysError failure = install_write_file(path, text, strlen(text));
    if (failure != 0) {
        ms_project_error_message(err, ms_arena_fmt(a, "write %s: %s", path, install_os_error(a, failure)).ptr);
        return false;
    }
    return true;
}

bool ms_install(MsArena *a, const MsInstallOptions *options, MsInstallReport *out, MsProjectError *err) {
    const uint32_t nroots = options->member_count > 0 ? options->member_count : 1;
    MsRoot *roots = MS_NEW_N(a, MsRoot, nroots);
    const char *lock_root = options->lock_root;
    if (options->member_count > 0) {
        for (uint32_t i = 0; i < nroots; i++) {
            MsProject *member = MS_NEW(a, MsProject);
            if (!ms_project_read(a, options->member_manifests[i], member, err)) {
                return false;
            }
            roots[i] = (MsRoot){.name = options->member_names[i], .manifest = {.deps = member->dependencies, .ndeps = member->dependency_count,
                                                                               .has_version = member->has_version, .version = member->version}};
        }
    } else {
        MsProject *project = MS_NEW(a, MsProject);
        if (!ms_project_read(a, options->manifest, project, err)) {
            return false;
        }
        if (project->is_workspace || install_in_workspace(a, project->root)) {
            ms_project_error_message(err, "this project is part of a workspace, which installs all of its members into one ms.lock; install them together");
            return false;
        }
        lock_root = project->root;
        roots[0] = (MsRoot){.name = "the project", .manifest = {.deps = project->dependencies, .ndeps = project->dependency_count,
                                                                 .has_version = project->has_version, .version = project->version}};
    }
    MsLock old;
    if (!ms_lock_read(a, lock_root, &old, err)) {
        return false;
    }
    Remote remote = {.arena = a, .cache = ms_package_cache_dir(a)};
    const MsRemote interface = {.user = &remote, .tags = remote_tags, .fetch = remote_fetch};
    MsResolved resolved;
    const char *failure;
    const bool resolved_ok = ms_resolve(a, roots, nroots, &old, options->update, options->update_count, &interface, &resolved, &failure);
    if (!resolved_ok) {
        ms_buf_free(&remote.records);
        ms_project_error_message(err, failure);
        return false;
    }
    if (!install_write_lock(a, lock_root, &resolved, options, err)) {
        ms_buf_free(&remote.records);
        return false;
    }
    out->count = resolved.ncopies;
    out->copies = MS_NEW_N(a, MsInstalledCopy, resolved.ncopies + 1);
    for (uint32_t i = 0; i < resolved.ncopies; i++) {
        out->copies[i] = (MsInstalledCopy){.name = install_root_name(&resolved, resolved.copies[i].id), .copy = resolved.copies[i],
                                           .state = MS_INSTALL_KEPT, .effects = "none"};
        for (size_t j = 0; j < MS_VEC_LEN(remote.records, CopyRecord); j++) {
            const CopyRecord *record = &MS_VEC_AT(remote.records, CopyRecord, j);
            if (strcmp(record->id, resolved.copies[i].id) == 0) {
                out->copies[i].state = record->state;
                out->copies[i].effects = record->effects;
            }
        }
    }
    ms_buf_free(&remote.records);
    if (out->count > 1) {
        qsort(out->copies, out->count, sizeof out->copies[0], install_copy_order);
    }
    return true;
}
