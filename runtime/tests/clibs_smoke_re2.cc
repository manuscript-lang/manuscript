// Links RE2 (and Abseil): matches a pattern with a capture group and rejects a pattern with a backreference.
#include <re2/re2.h>
#include <cstdio>
#include <string>
int main() {
    std::string year;
    if (!RE2::PartialMatch("released 2026-11-20", "(\\d{4})-\\d{2}-\\d{2}", &year) || year != "2026") return 1;
    RE2 backref("(a)\\1");
    if (backref.ok()) return 2;  // linear-time engine: no backreferences
    std::printf("re2 ok\n");
    return 0;
}
