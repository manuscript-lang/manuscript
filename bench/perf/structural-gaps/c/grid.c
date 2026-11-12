#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
int64_t lcs(int64_t*a,int n,int64_t*b,int m){int64_t**dp=malloc((n+1)*sizeof*dp);for(int i=0;i<=n;i++)dp[i]=calloc(m+1,8);
for(int i=1;i<=n;i++)for(int j=1;j<=m;j++){if(a[i-1]==b[j-1])dp[i][j]=dp[i-1][j-1]+1;else if(dp[i-1][j]>=dp[i][j-1])dp[i][j]=dp[i-1][j];else dp[i][j]=dp[i][j-1];}return dp[n][m];}
int main(){int64_t a[2000],b[2000];for(int i=0;i<2000;i++){a[i]=i*7%13;b[i]=i*5%11;}printf("%lld\n",(long long)lcs(a,2000,b,2000));}
