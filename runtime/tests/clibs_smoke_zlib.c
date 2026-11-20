/* Links zlib: compresses a buffer, expands it again and compares, and checks a known CRC-32. */
#include <stdio.h>
#include <string.h>
#include <zlib.h>

int main(void) {
    unsigned char text[4096], packed[4200], back[4096];
    for (size_t i = 0; i < sizeof text; i++) text[i] = (unsigned char)("manuscript"[i % 10]);
    uLongf packed_len = sizeof packed, back_len = sizeof back;
    if (compress2(packed, &packed_len, text, sizeof text, 6) != Z_OK || packed_len >= sizeof text) return 1;
    if (uncompress(back, &back_len, packed, packed_len) != Z_OK || back_len != sizeof text) return 2;
    if (memcmp(text, back, sizeof text) != 0) return 3;
    if (crc32(0, (const unsigned char *)"123456789", 9) != 0xCBF43926UL) return 4;
    printf("zlib %s ok\n", zlibVersion());
    return 0;
}
