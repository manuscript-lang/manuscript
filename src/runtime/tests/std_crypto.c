/* Replays src/runtime/tests/oracle/crypto.tsv (recorded from Go's crypto packages) against src/runtime/std/crypto.c. */
#include <stdio.h>

#include "append.h"

#include "ms_rt/crypto.h"
#include "fake_rt.h"

typedef MsVec vec;

/* The fake runtime stores 8-byte elements; Bytes here are byte buffers, as the real runtime writes them. */
static vec from_hex(const char *tok) {
    vec v = {NULL, 0, 0};
    size_t n = strlen(tok + 1) / 2;
    if (n) {
        v.ptr = malloc(n);
        for (size_t i = 0; i < n; i++) {
            unsigned b;
            sscanf(tok + 1 + 2 * i, "%2x", &b);
            ((uint8_t *)v.ptr)[i] = (uint8_t)b;
        }
    }
    v.len = v.cap = n;
    return v;
}

/* The size of the result buffers of the replay loops below. */
enum { RESULT_CAP = 1 << 16 };

static void put_hex(char *dst, const vec *v) {
    char *p = dst + strlen(dst);
    *p++ = 'x';
    for (size_t i = 0; i < v->len; i++) p += snprintf(p, 3, "%02x", ((uint8_t *)v->ptr)[i]); /* two digits and the NUL */
    *p = 0;
}

static const char *status_name(int st) {
    switch (st) {
    case 1: return "InvalidInput";
    case 3: return "LimitExceeded";
    case 9: return "Unsupported";
    case 18: return "AuthenticationFailed";
    default: return "Other";
    }
}

/* ok <hex> or err <name>; results over 1 KiB are recorded as their length and SHA-256. */
static void result(char *dst, int st, vec *out) {
    if (st) {
        snprintf(dst + strlen(dst), RESULT_CAP - strlen(dst), "err %s", status_name(st));
        return;
    }
    msx_append(dst, RESULT_CAP, "ok ");
    if (out->len > 1024) {
        vec d = {NULL, 0, 0}, one = {out->ptr, out->len, out->len};
        char tmp[16] = "";
        msstd_crypto_digest(3, &one, &d);
        snprintf(tmp, sizeof tmp, "x#%zu:", out->len);
        msx_append(dst, RESULT_CAP, "%s", tmp);
        put_hex(dst + strlen(dst), &d);
        memmove(dst + strlen(dst) - 2 * d.len - 1, dst + strlen(dst) - 2 * d.len, 2 * d.len + 1); /* drop the extra x */
        free(d.ptr);
    } else {
        put_hex(dst, out);
    }
}

int main(void) {
    FILE *f = fopen("src/runtime/tests/oracle/crypto.tsv", "r");
    if (!f) {
        puts("cannot open the oracle");
        return 1;
    }
    static char line[1 << 20], want[1 << 16], got[RESULT_CAP];
    int cases = 0, failures = 0;
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\n")] = 0;
        char orig[256];
        snprintf(orig, sizeof orig, "%.200s", line);
        if (line[0] == '#' || !line[0]) continue;
        char *field[16];
        int nf = 0, arrow = -1;
        for (char *p = line; *p && nf < 16;) { /* tab-separated fields */
            p += strspn(p, "\t");
            if (!*p) break;
            char *start = p;
            p += strcspn(p, "\t");
            if (*p) *p++ = 0;
            if (!strcmp(start, "=>")) arrow = nf;
            field[nf++] = start;
        }
        want[0] = 0;
        for (int i = arrow + 1; i < nf; i++) msx_append(want, sizeof want, "%s%s", i > arrow + 1 ? "\t" : "", field[i]);
        if (arrow == nf - 1) msx_append(want, sizeof want, "%s", ""); /* an empty result: the oracle writes nothing after the arrow */
        char **a = field + 1;
        got[0] = 0;
        const char *kind = field[0];
        vec out = {NULL, 0, 0};
        int st = 0;
        int64_t alg = strtoll(a[0], NULL, 10);
        if (!strcmp(kind, "digest")) {
            vec d = from_hex(a[1]);
            msstd_crypto_digest(alg, &d, &out);
            put_hex(got, &out);
            free(d.ptr);
        } else if (!strcmp(kind, "hmac")) {
            vec k = from_hex(a[1]), d = from_hex(a[2]);
            st = msstd_crypto_hmac(alg, &k, &d, &out);
            msx_append(got, sizeof got, "%s", "ok ");
            put_hex(got, &out);
            free(k.ptr), free(d.ptr);
        } else if (!strcmp(kind, "pbkdf2") || !strcmp(kind, "hkdf")) {
            vec p = from_hex(a[1]), s = from_hex(a[2]);
            if (kind[0] == 'p') {
                st = msstd_crypto_derive_key(alg, &p, &s, strtoll(a[3], NULL, 10), strtoll(a[4], NULL, 10), &out);
            } else {
                vec info = from_hex(a[3]);
                st = msstd_crypto_hkdf(alg, &p, &s, &info, strtoll(a[4], NULL, 10), &out);
                free(info.ptr);
            }
            result(got, st, &out);
            free(p.ptr), free(s.ptr);
        } else if (!strcmp(kind, "hasher")) {
            vec d1 = from_hex(a[2]), d2 = from_hex(a[3]), key = a[1][0] == '-' ? (vec){0} : from_hex(a[1]);
            void *h = a[1][0] == '-' ? msstd_crypto_hasher_new(alg) : msstd_crypto_hmac_hasher_new(alg, &key);
            msstd_crypto_hasher_update(h, &d1);
            msstd_crypto_hasher_update(h, &d2);
            vec r1 = {0}, r2 = {0};
            msstd_crypto_hasher_finish(h, &r1);
            msstd_crypto_hasher_finish(h, &r2);
            put_hex(got, &r1);
            msx_append(got, sizeof got, "%s", "\t");
            put_hex(got, &r2);
            ((MsObj *)h)->drop(h);
            free(d1.ptr), free(d2.ptr), free(key.ptr), free(r1.ptr), free(r2.ptr);
        } else if (!strcmp(kind, "cteq")) {
            vec l = from_hex(a[0]), r = from_hex(a[1]);
            msx_append(got, sizeof got, "%s", msstd_crypto_constant_time_equal(&l, &r) ? "1" : "0");
            free(l.ptr), free(r.ptr);
        } else if (!strcmp(kind, "verify")) {
            vec k = from_hex(a[0]), d = from_hex(a[1]), s = from_hex(a[2]);
            msx_append(got, sizeof got, "%s", msstd_crypto_verify(&k, &d, &s) ? "1" : "0");
            free(k.ptr), free(d.ptr), free(s.ptr);
        } else {
            vec x = from_hex(a[0]), y = nf - arrow > 3 || !strcmp(kind, "pubkey") ? (vec){0} : (vec){0};
            if (!strcmp(kind, "pubkey")) {
                st = msstd_crypto_public_key(&x, &out);
            } else if (!strcmp(kind, "sign")) {
                y = from_hex(a[1]);
                st = msstd_crypto_sign(&x, &y, &out);
            } else if (!strcmp(kind, "seal") || !strcmp(kind, "open")) {
                vec n = from_hex(a[1]), d = from_hex(a[2]), aad = from_hex(a[3]);
                st = kind[0] == 's' ? msstd_crypto_seal(&x, &n, &d, &aad, &out) : msstd_crypto_open(&x, &n, &d, &aad, &out);
                free(n.ptr), free(d.ptr), free(aad.ptr);
            } else {
                vec iv = from_hex(a[1]), d = from_hex(a[2]);
                st = !strcmp(kind, "ctr")      ? msstd_crypto_aes_ctr(&x, &iv, &d, &out)
                     : !strcmp(kind, "cbcenc") ? msstd_crypto_aes_cbc_encrypt(&x, &iv, &d, &out)
                                               : msstd_crypto_aes_cbc_decrypt(&x, &iv, &d, &out);
                free(iv.ptr), free(d.ptr);
            }
            result(got, st, &out);
            free(x.ptr), free(y.ptr);
        }
        free(out.ptr);
        cases++;
        if (strcmp(got, want)) {
            if (failures++ < 10) printf("FAIL %s: got %.120s want %.120s | %.200s\n", kind, got, want, orig);
        }
    }
    fclose(f);
    if (cases < 2000) failures++;
    if (failures) {
        printf("%d of %d cases failed\n", failures, cases);
        return 1;
    }
    printf("std_crypto ok (%d cases)\n", cases);
    return 0;
}
