/* Unit tests for the stage table, the command plan and the parse entry point. */
#include <stdio.h>
#include <string.h>

#include "ms/driver.h"

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failures++; } } while (0)

int main(void) {
    MsStageTable table = ms_stage_table_default();
    CHECK(table.impl[MS_STAGE_PARSE] == MS_IMPL_C);
    CHECK(table.impl[MS_STAGE_CHECK] == MS_IMPL_RUST);
    CHECK(ms_stage_table_override(&table, "parse=rust,check=c"));
    CHECK(table.impl[MS_STAGE_PARSE] == MS_IMPL_RUST && table.impl[MS_STAGE_CHECK] == MS_IMPL_C);
    CHECK(!ms_stage_table_override(&table, "parse=c,bogus=c"));
    CHECK(table.impl[MS_STAGE_PARSE] == MS_IMPL_RUST); /* untouched by the failed override */
    CHECK(!ms_stage_table_override(&table, "parse"));
    table = ms_stage_table_default();
    CHECK(ms_command_stages("nonsense") == 0);
    CHECK(ms_command_stages("fmt") & (1u << MS_STAGE_FORMAT));
    CHECK(!ms_command_in_c(&table, "fmt"));
    CHECK(!ms_command_in_c(&table, "nonsense"));

    MsCompiler c;
    ms_compiler_init(&c);
    MsSource src;
    MsDiag diag;
    const char *ok = "fn main() Int:\n\treturn 0\n";
    CHECK(ms_load_text(&c, "ok.ms", ok, strlen(ok), &src, &diag) == MS_OK);
    CHECK(src.module.ndecls == 1);
    const char *bad = "fn main( {\n";
    CHECK(ms_load_text(&c, "bad.ms", bad, strlen(bad), &src, &diag) == MS_ERR_SYNTAX);
    CHECK(diag.message.len > 0);
    CHECK(ms_load_text(&c, "u.ms", "\xff", 1, &src, &diag) == MS_ERR_UTF8);
    CHECK(ms_load_file(&c, "/nonexistent/x.ms", &src, &diag) == MS_ERR_IO);
    ms_compiler_free(&c);
    if (failures == 0) {
        puts("driver tests ok");
    }
    return failures != 0;
}
