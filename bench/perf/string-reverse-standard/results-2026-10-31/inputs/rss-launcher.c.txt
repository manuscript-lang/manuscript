/* Isolate child RSS from the Python launcher's inherited high-water mark. Linux/Unix only.
 * gcc -O2 rss.c -o rss; rss metrics.json program args... (stdin/stdout inherited). */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    pid_t child = fork();
    if (child < 0) return 2;
    if (child == 0) {
        execvp(argv[2], argv + 2);
        _exit(127);
    }
    int status;
    if (waitpid(child, &status, 0) < 0) return 2;
    struct rusage usage;
    if (getrusage(RUSAGE_CHILDREN, &usage)) return 2;
    FILE *out = fopen(argv[1], "w");
    if (!out) return 2;
    fprintf(out, "{\"maxrss_kib\":%ld}\n", usage.ru_maxrss);
    if (fclose(out)) return 2;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
