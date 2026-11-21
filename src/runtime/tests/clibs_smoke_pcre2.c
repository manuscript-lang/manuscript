/* Links PCRE2: matches a pattern with a capture group, and shows that match, depth and heap limits
   stop a pattern that backtracks without bound, and that the pattern cannot raise them. */
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <stdio.h>
#include <string.h>

static pcre2_code *compile(const char *pattern) {
    int code; PCRE2_SIZE at;
    return pcre2_compile((PCRE2_SPTR)pattern, PCRE2_ZERO_TERMINATED, PCRE2_UTF, &code, &at, NULL);
}

int main(void) {
    pcre2_code *date = compile("(\\d{4})-\\d{2}-\\d{2}");
    if (!date) return 1;
    pcre2_match_data *found = pcre2_match_data_create_from_pattern(date, NULL);
    const char *text = "released 2026-11-20";
    if (pcre2_match(date, (PCRE2_SPTR)text, strlen(text), 0, 0, found, NULL) != 2) return 2;
    PCRE2_SIZE *at = pcre2_get_ovector_pointer(found);
    if (at[3] - at[2] != 4 || memcmp(text + at[2], "2026", 4) != 0) return 3;
    pcre2_match_data_free(found); pcre2_code_free(date);

    pcre2_code *slow = compile("(a+)+$");
    if (!slow) return 4;
    pcre2_match_context *limits = pcre2_match_context_create(NULL);
    pcre2_set_match_limit(limits, 100000);
    pcre2_set_depth_limit(limits, 1000);
    pcre2_set_heap_limit(limits, 1024); /* KiB */
    found = pcre2_match_data_create_from_pattern(slow, NULL);
    const char *hard = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!";
    if (pcre2_match(slow, (PCRE2_SPTR)hard, strlen(hard), 0, 0, found, limits) != PCRE2_ERROR_MATCHLIMIT) return 5;
    pcre2_match_data_free(found); pcre2_code_free(slow);

    /* A pattern cannot raise the caller's limit from inside: (*LIMIT_MATCH=n) only lowers it. */
    pcre2_code *raised = compile("(*LIMIT_MATCH=4000000000)(a+)+$");
    if (!raised) return 6;
    found = pcre2_match_data_create_from_pattern(raised, NULL);
    if (pcre2_match(raised, (PCRE2_SPTR)hard, strlen(hard), 0, 0, found, limits) != PCRE2_ERROR_MATCHLIMIT) return 7;
    pcre2_match_data_free(found); pcre2_match_context_free(limits); pcre2_code_free(raised);

    char version[32]; pcre2_config(PCRE2_CONFIG_VERSION, version);
    printf("pcre2 %s ok\n", version);
    return 0;
}
