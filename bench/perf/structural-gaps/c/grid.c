// C twin of grid.ms: LCS over a 2001 x 2001 table of rows (gcc -O2).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    enum { N = 2000 };
    int64_t a[N], b[N], x = 12345;
    for (int k = 0; k < N; k++) {
        x = (x * 1103515245 + 12345) % 2147483648;
        a[k] = (x / 65536) % 4;
        x = (x * 1103515245 + 12345) % 2147483648;
        b[k] = (x / 65536) % 4;
    }
    int64_t **dp = malloc((N + 1) * sizeof *dp);
    for (int i = 0; i <= N; i++) dp[i] = calloc(N + 1, sizeof **dp);
    for (int i = 1; i <= N; i++)
        for (int j = 1; j <= N; j++) {
            if (a[i - 1] == b[j - 1]) dp[i][j] = dp[i - 1][j - 1] + 1;
            else if (dp[i - 1][j] >= dp[i][j - 1]) dp[i][j] = dp[i - 1][j];
            else dp[i][j] = dp[i][j - 1];
        }
    printf("%lld\n", (long long)dp[N][N]);
    return 0;
}
