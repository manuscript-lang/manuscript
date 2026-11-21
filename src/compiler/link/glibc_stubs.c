/* Owns making the glibc stand-in libraries (see glibc_stubs.h). */
#include "compiler/link/glibc_stubs.h"

#include "base/bytes.h"
#include "base/file.h"
#include "base/intern.h"
#include "base/path.h"
#include "base/process.h"
#include "compiler/link/glibc_table.h"

#if defined(__aarch64__)
#define STUB_TRIPLE "-mtriple=aarch64-unknown-linux-gnu"
#define LOADER_NAME "ld-linux-aarch64.so.1"
#else
#define STUB_TRIPLE "-mtriple=x86_64-unknown-linux-gnu"
#define LOADER_NAME "ld-linux-x86-64.so.2"
#endif

const char *const link_glibc_libraries[] = {"libpthread.so.0", "libc.so.6", "libm.so.6", "libdl.so.2",
                                            "librt.so.1", LOADER_NAME};
const size_t link_glibc_library_count = MS_COUNT_OF(link_glibc_libraries);

typedef struct StubFiles {
  MsString source, object, script, log, library; /* owned paths inside the stage directory */
} StubFiles;

static MsString path_in(MsSpan directory, MsSpan name, const char *suffix) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, directory, name);
  ms_strbuild_append_text(&path, suffix);
  return ms_strbuild_finish(&path);
}

static StubFiles stub_files(MsSpan stage, MsSpan soname) {
  return (StubFiles){.source = path_in(stage, soname, ".ll"), .object = path_in(stage, soname, ".o"),
                     .script = path_in(stage, soname, ".map"), .log = path_in(stage, soname, ".log"),
                     .library = path_in(stage, soname, "")};
}

static void stub_files_free(StubFiles *files) {
  ms_string_release(&files->source);
  ms_string_release(&files->object);
  ms_string_release(&files->script);
  ms_string_release(&files->log);
  ms_string_release(&files->library);
}

static bool has_soname(const GlibcExport *entry, MsSpan soname) {
  return ms_span_equal(entry->soname, soname);
}

/* One definition per export: a function, or zeroed storage of the size copy relocations need. */
static void append_definition(MsStrBuild *ir, const GlibcExport *entry) {
  if (entry->data) {
    ms_strbuild_append_text(ir, "@\"");
    ms_strbuild_append(ir, entry->name);
    ms_strbuild_append_text(ir, "\" = global [");
    ms_strbuild_append_u64(ir, entry->size == 0 ? 1 : entry->size);
    ms_strbuild_append_text(ir, " x i8] zeroinitializer, align 8\n");
    return;
  }
  ms_strbuild_append_text(ir, "define void @\"");
  ms_strbuild_append(ir, entry->name);
  ms_strbuild_append_text(ir, "\"() {\n  ret void\n}\n");
}

static bool has_span(const MsSpanList *items, MsSpan value) {
  for (size_t index = 0; index < items->len; index++) {
    if (ms_span_equal(items->ptr[index], value)) {
      return true;
    }
  }
  return false;
}

/* The version script: one node per version of the library, each naming its symbols. */
static void append_script(MsStrBuild *script, const GlibcExportList *all, MsSpan soname) {
  MsSpanList versions = {0};
  for (size_t index = 0; index < all->len; index++) {
    const GlibcExport *entry = &all->ptr[index];
    if (has_soname(entry, soname) && !has_span(&versions, entry->version)) {
      ms_span_list_push(&versions, entry->version);
    }
  }
  for (size_t v = 0; v < versions.len; v++) {
    ms_strbuild_append(script, versions.ptr[v]);
    ms_strbuild_append_text(script, " { global:");
    for (size_t index = 0; index < all->len; index++) {
      const GlibcExport *entry = &all->ptr[index];
      if (has_soname(entry, soname) && ms_span_equal(entry->version, versions.ptr[v])) {
        ms_strbuild_append_byte(script, ' ');
        ms_strbuild_append(script, entry->name);
        ms_strbuild_append_byte(script, ';');
      }
    }
    ms_strbuild_append_text(script, " };\n");
  }
  ms_span_list_free(&versions);
}

static bool write_sources(const StubFiles *files, const GlibcExportList *all, MsSpan soname, MsStrBuild *why) {
  MsStrBuild ir = ms_strbuild_new();
  MsStrBuild script = ms_strbuild_new();
  for (size_t index = 0; index < all->len; index++) {
    if (has_soname(&all->ptr[index], soname)) {
      append_definition(&ir, &all->ptr[index]);
    }
  }
  append_script(&script, all, soname);
  bool ok = ms_file_write(ms_string_span(&files->source), ms_strbuild_span(&ir)) &&
            ms_file_write(ms_string_span(&files->script), ms_strbuild_span(&script));
  if (!ok) {
    ms_strbuild_append_text(why, "cannot write the glibc stub of ");
    ms_strbuild_append(why, soname);
  }
  ms_strbuild_free(&ir);
  ms_strbuild_free(&script);
  return ok;
}

static bool compile_and_link(const LinkOptions *options, const StubFiles *files, MsSpan soname, MsStrBuild *why) {
  MsSpan llc[] = {options->llc, ms_span_of_text("-filetype=obj"), ms_span_of_text("-relocation-model=pic"),
                  ms_span_of_text(STUB_TRIPLE), ms_string_span(&files->source), ms_span_of_text("-o"),
                  ms_string_span(&files->object)};
  MsProcessSpec llc_spec = {.argv = llc, .argc = MS_COUNT_OF(llc), .directory = ms_span_of(NULL, 0),
                            .log_path = ms_string_span(&files->log)};
  if (!ms_process_run_logged(ms_span_of_text("llc (glibc stubs)"), &llc_spec, why)) {
    return false;
  }
  MsSpan lld[] = {options->lld, ms_span_of_text("-flavor"), ms_span_of_text("gnu"), ms_span_of_text("-shared"),
                  ms_span_of_text("-soname"), soname, ms_span_of_text("--version-script"),
                  ms_string_span(&files->script), ms_span_of_text("-o"), ms_string_span(&files->library),
                  ms_string_span(&files->object)};
  MsProcessSpec lld_spec = {.argv = lld, .argc = MS_COUNT_OF(lld), .directory = ms_span_of(NULL, 0),
                            .log_path = ms_string_span(&files->log)};
  return ms_process_run_logged(ms_span_of_text("lld (glibc stubs)"), &lld_spec, why);
}

/* Builds the stub of one library into `stage`, leaving only the library there. */
static bool build_stub(const LinkOptions *options, MsSpan stage, const GlibcExportList *all, MsSpan soname,
                       MsStrBuild *why) {
  StubFiles files = stub_files(stage, soname);
  bool ok = write_sources(&files, all, soname, why) && compile_and_link(options, &files, soname, why);
  ms_path_remove(ms_string_span(&files.source));
  ms_path_remove(ms_string_span(&files.object));
  ms_path_remove(ms_string_span(&files.script));
  ms_path_remove(ms_string_span(&files.log));
  stub_files_free(&files);
  return ok;
}

static bool build_all(const LinkOptions *options, MsSpan stage, MsStrBuild *why) {
  MsString table_path = path_in(options->files, ms_span_of_text("glibc.symbols"), "");
  MsBytes table = {0};
  if (!ms_file_read(ms_string_span(&table_path), &table)) {
    ms_strbuild_append_text(why, "cannot read the symbol table for the glibc stubs in ");
    ms_strbuild_append(why, ms_string_span(&table_path));
    ms_string_release(&table_path);
    return false;
  }
  GlibcExportList exports = {0};
  glibc_table_parse(ms_bytes_span(&table), &exports);
  bool ok = true;
  for (size_t index = 0; ok && index < link_glibc_library_count; index++) {
    ok = build_stub(options, stage, &exports, ms_span_of_text(link_glibc_libraries[index]), why);
  }
  glibc_export_list_free(&exports);
  ms_bytes_free(&table);
  ms_string_release(&table_path);
  return ok;
}

static void remove_stage(MsSpan stage) {
  ms_path_remove_tree(stage);
}

bool link_glibc_stubs(const LinkOptions *options, MsString *directory, MsStrBuild *why) {
  *directory = path_in(options->files, ms_span_of_text("glibc"), "");
  MsString done = path_in(ms_string_span(directory), ms_span_of_text(".ok"), "");
  bool present = ms_file_is_regular(ms_string_span(&done));
  ms_string_release(&done);
  if (present) {
    return true;
  }
  MsString stage = ms_string_empty();
  if (!ms_dir_make_temp(options->files, ms_span_of_text(".glibc-"), &stage)) {
    ms_strbuild_append_text(why, "cannot create the glibc stubs in ");
    ms_strbuild_append(why, ms_string_span(directory));
    return false;
  }
  MsString stage_done = path_in(ms_string_span(&stage), ms_span_of_text(".ok"), "");
  bool ok = build_all(options, ms_string_span(&stage), why) && ms_file_write(ms_string_span(&stage_done), ms_span_of(NULL, 0));
  bool installed = ok && ms_file_rename(ms_string_span(&stage), ms_string_span(directory));
  if (!installed) {
    remove_stage(ms_string_span(&stage));
    MsString winner = path_in(ms_string_span(directory), ms_span_of_text(".ok"), "");
    installed = ok && ms_file_is_regular(ms_string_span(&winner)); /* another build installed its set first */
    ms_string_release(&winner);
    if (ok && !installed) {
      ms_strbuild_append_text(why, "cannot install the glibc stubs in ");
      ms_strbuild_append(why, ms_string_span(directory));
    }
  }
  ms_string_release(&stage_done);
  ms_string_release(&stage);
  return installed;
}
