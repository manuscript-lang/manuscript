/* Unit test of the public suffix wiring: the table compiled into libpsl knows registry suffixes, and libcurl was built to use it
 * (so its cookie jar refuses `Domain=co.uk`). */
#include <stdio.h>

#include <curl/curl.h>
#include <libpsl.h>

static int failures;

static void expect(int condition, const char *what) {
  if (!condition) {
    (void)printf("FAIL: %s\n", what);
    failures++;
  }
}

int main(void) {
  const psl_ctx_t *list = psl_builtin();
  expect(list != NULL, "the public suffix list is built in");
  if (list == NULL) {
    return 1;
  }
  expect(psl_is_public_suffix(list, "co.uk") != 0, "co.uk is a public suffix");
  expect(psl_is_public_suffix(list, "github.io") != 0, "github.io is a public suffix");
  expect(psl_is_public_suffix(list, "com") != 0, "com is a public suffix");
  expect(psl_is_public_suffix(list, "example.co.uk") == 0, "example.co.uk is a registrable name");
  expect(psl_is_public_suffix(list, "example.com") == 0, "example.com is a registrable name");
  const curl_version_info_data *info = curl_version_info(CURLVERSION_NOW);
  expect((info->features & CURL_VERSION_PSL) != 0, "libcurl is built with the public suffix list");
  return failures == 0 ? 0 : 1;
}
