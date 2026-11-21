/* Replays src/runtime/tests/oracle/crypto_asym.tsv (recorded from Go) against src/runtime/std/crypto_asym.c. Randomized
   operations (ECDSA, PSS, OAEP) are checked for success or failure only. */
#include <stdio.h>

#include "append.h"

#include "ms_rt/crypto.h"
#include "fake_rt.h"

typedef MsVec vec;

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
    case 9: return "Unsupported";
    case 18: return "AuthenticationFailed";
    default: return "Other";
    }
}
/* ok <hex> (over 1 KiB: x#length:sha256) or err <name> */
static void result(char *dst, int st, vec *out) {
    if (st) {
        snprintf(dst + strlen(dst), RESULT_CAP - strlen(dst), "err %s", status_name(st));
        return;
    }
    msx_append(dst, RESULT_CAP, "ok ");
    if (out->len > 1024) {
        vec d = {0};
        msstd_crypto_digest(3, out, &d);
        snprintf(dst + strlen(dst), RESULT_CAP - strlen(dst), "x#%zu:", out->len);
        char *p = dst + strlen(dst);
        for (size_t i = 0; i < d.len; i++) p += snprintf(p, 3, "%02x", ((uint8_t *)d.ptr)[i]);
        free(d.ptr);
    } else {
        put_hex(dst, out);
    }
}

typedef struct { char name[32]; vec priv, pub; } keyrec;
static keyrec keys[64];
static int nkeys;
static keyrec *key_named(const char *n) {
    for (int i = 0; i < nkeys; i++)
        if (!strcmp(keys[i].name, n)) return &keys[i];
    printf("no key %s\n", n);
    exit(1);
}

int main(void) {
    FILE *f = fopen("src/runtime/tests/oracle/crypto_asym.tsv", "r");
    if (!f) {
        puts("cannot open the oracle");
        return 1;
    }
    static char line[1 << 20], want[1 << 16], got[RESULT_CAP];
    int cases = 0, failures = 0;
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == '#' || !line[0]) continue;
        char orig[256];
        snprintf(orig, sizeof orig, "%.200s", line);
        char *field[16];
        int nf = 0, arrow = -1;
        /* fields may be empty ("x" is the empty value, so none are), split on tabs */
        for (char *p = line; *p && nf < 16;) { /* tab-separated fields */
            p += strspn(p, "\t");
            if (!*p) break;
            char *start = p;
            p += strcspn(p, "\t");
            if (*p) *p++ = 0;
            if (!strcmp(start, "=>")) arrow = nf;
            field[nf++] = start;
        }
        const char *kind = field[0];
        char **a = field + 1;
        if (!strcmp(kind, "key")) {
            keyrec *k = &keys[nkeys++];
            snprintf(k->name, sizeof k->name, "%s", a[0]);
            k->priv = from_hex(a[1]);
            k->pub = from_hex(a[2]);
            continue;
        }
        if (!strcmp(kind, "pt")) {
            keyrec *k = &keys[nkeys++];
            snprintf(k->name, sizeof k->name, "%s", a[0]);
            k->priv = (vec){0};
            k->pub = from_hex(a[1]);
            continue;
        }
        want[0] = 0;
        if (arrow >= 0)
            for (int i = arrow + 1; i < nf; i++) msx_append(want, sizeof want, "%s%s", i > arrow + 1 ? "\t" : "", field[i]);
        got[0] = 0;
        vec out = {0};
        int st = 0;
        int64_t alg = nf > 2 ? strtoll(a[1], NULL, 10) : 0;
        if (!strcmp(kind, "rsagen")) {
            int64_t bits = strtoll(a[0], NULL, 10);
            st = msstd_crypto_rsa_generate(bits, &out);
            if (!st && out.len) { /* random: only success and a sane size are compared */
                free(out.ptr);
                out = (vec){0};
            }
            if (!strncmp(want, "ok ", 3)) {
                msx_append(got, sizeof got, "%s", st ? "failed" : want);
            } else {
                result(got, st, &out);
            }
        } else if (!strcmp(kind, "pub")) {
            st = msstd_crypto_public_key_der(&key_named(a[0])->priv, &out);
            result(got, st, &out);
        } else if (!strcmp(kind, "ecsign")) {
            vec d = from_hex(a[2]);
            st = msstd_crypto_ecdsa_sign(&key_named(a[0])->priv, alg, &d, &out);
            msx_append(got, sizeof got, "%s", st ? "0" : "1");
            free(d.ptr);
        } else if (!strcmp(kind, "ecverify") || !strcmp(kind, "rsaverify") || !strcmp(kind, "pssverify")) {
            vec d = from_hex(a[2]), s = from_hex(a[3]);
            const vec *k = &key_named(a[0])->pub;
            int ok = kind[0] == 'e' ? msstd_crypto_ecdsa_verify(k, alg, &d, &s)
                     : kind[0] == 'r' ? msstd_crypto_rsa_verify(k, alg, &d, &s)
                                      : msstd_crypto_rsa_verify_pss(k, alg, &d, &s);
            msx_append(got, sizeof got, "%s", ok ? "1" : "0");
            free(d.ptr);
            free(s.ptr);
        } else if (!strcmp(kind, "ecdh")) {
            st = msstd_crypto_ecdh_shared_secret(&key_named(a[0])->priv, &key_named(a[1])->pub, &out);
            result(got, st, &out);
        } else if (!strcmp(kind, "rsasign")) {
            vec d = from_hex(a[2]);
            st = msstd_crypto_rsa_sign(&key_named(a[0])->priv, alg, &d, &out);
            result(got, st, &out);
            free(d.ptr);
        } else if (!strcmp(kind, "rsaenc")) {
            const size_t m_len = (size_t)strtoll(a[2], NULL, 10);
            vec m = {malloc(m_len + 1), m_len, 0};
            memset(m.ptr, 7, m.len);
            st = msstd_crypto_rsa_encrypt(&key_named(a[0])->pub, alg, &m, &out);
            msx_append(got, sizeof got, "%s", st ? "0" : "1");
            free(m.ptr);
        } else if (!strcmp(kind, "rsadec")) {
            vec c = from_hex(a[2]);
            st = msstd_crypto_rsa_decrypt(&key_named(a[0])->priv, alg, &c, &out);
            result(got, st, &out);
            free(c.ptr);
        } else {
            printf("unknown case %s\n", kind);
            return 1;
        }
        free(out.ptr);
        cases++;
        if (strcmp(got, want) && failures++ < 12) printf("FAIL got %.100s want %.100s | %.150s\n", got, want, orig);
    }
    fclose(f);
    for (int i = 0; i < nkeys; i++) {
        free(keys[i].priv.ptr);
        free(keys[i].pub.ptr);
    }

    /* Generated keys: sign, verify, agree, encrypt and decrypt round trip. */
    for (int curve = 0; curve < 3; curve++) {
        vec a = {0}, b = {0}, pa = {0}, pb = {0}, sig = {0}, m = {(void *)(uintptr_t)"m", 1, 1}, n = {(void *)(uintptr_t)"n", 1, 1};
        int ok = !msstd_crypto_ecdsa_generate(curve, &a) && !msstd_crypto_ecdsa_generate(curve, &b) &&
                 !msstd_crypto_public_key_der(&a, &pa) && !msstd_crypto_public_key_der(&b, &pb) &&
                 !msstd_crypto_ecdsa_sign(&a, 3, &m, &sig) && msstd_crypto_ecdsa_verify(&pa, 3, &m, &sig) &&
                 !msstd_crypto_ecdsa_verify(&pb, 3, &m, &sig) && !msstd_crypto_ecdsa_verify(&pa, 3, &n, &sig);
        vec s1 = {0}, s2 = {0};
        ok = ok && !msstd_crypto_ecdh_shared_secret(&a, &pb, &s1) && !msstd_crypto_ecdh_shared_secret(&b, &pa, &s2) &&
             s1.len == s2.len && s1.len && !memcmp(s1.ptr, s2.ptr, s1.len);
        if (!ok) {
            printf("FAIL generated curve %d\n", curve);
            failures++;
        }
        free(a.ptr);
        free(b.ptr);
        free(pa.ptr);
        free(pb.ptr);
        free(sig.ptr);
        free(s1.ptr);
        free(s2.ptr);
    }
    {
        vec k = {0}, p = {0}, m = {(void *)(uintptr_t)"secret", 6, 6}, sig = {0}, c = {0}, back = {0};
        int ok = !msstd_crypto_rsa_generate(2048, &k) && !msstd_crypto_public_key_der(&k, &p);
        for (int alg = 3; ok && alg <= 5; alg += 2) {
            ok = !msstd_crypto_rsa_sign_pss(&k, alg, &m, &sig) && msstd_crypto_rsa_verify_pss(&p, alg, &m, &sig) &&
                 !msstd_crypto_rsa_encrypt(&p, alg, &m, &c) && !msstd_crypto_rsa_decrypt(&k, alg, &c, &back) &&
                 back.len == 6 && !memcmp(back.ptr, "secret", 6);
            if (alg == 3) {
                free(sig.ptr);
                free(c.ptr);
                free(back.ptr);
            }
        }
        if (!ok) {
            printf("FAIL generated rsa\n");
            failures++;
        }
        free(k.ptr);
        free(p.ptr);
        free(sig.ptr);
        free(c.ptr);
        free(back.ptr);
    }
    if (cases < 1000) failures++;
    if (failures) {
        printf("%d failures in %d cases\n", failures, cases);
        return 1;
    }
    printf("std_crypto_asym ok (%d cases)\n", cases);
    return 0;
}
