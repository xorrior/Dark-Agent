/*
 * Crystal runtime bootstrap for dylib builds.
 *
 * When the dylib is loaded via dlopen(), this constructor runs automatically
 * and initializes Crystal's runtime (event loop, fiber scheduler, top-level
 * require/init code) by calling Crystal's generated main().
 *
 * Problem: Crystal's main() calls exit() after running top-level code, which
 * would terminate the host process during dlopen(). We intercept this by
 * registering an atexit handler that longjmp's back to the constructor before
 * the process can terminate.
 *
 * After this constructor completes, the C-exported `dark_agent_init` symbol
 * (defined in dark-agent-dylib.cr) is safe to call.
 */

#include <stddef.h>
#include <stdlib.h>
#include <setjmp.h>

static jmp_buf exit_jmp;
static volatile int should_intercept = 0;

extern int main(int argc, char **argv);

static void exit_handler(void) {
    if (should_intercept) {
        should_intercept = 0;
        longjmp(exit_jmp, 1);
    }
}

__attribute__((constructor))
static void crystal_dylib_init(void) {
    char *argv[] = { "dark-agent", NULL };
    atexit(exit_handler);
    should_intercept = 1;
    if (setjmp(exit_jmp) == 0) {
        main(1, argv);
        /* main returned normally (no exit call) */
    }
    /* Either main returned or exit() was intercepted — runtime is initialized */
    should_intercept = 0;
}
