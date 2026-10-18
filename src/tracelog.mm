#import "tracelog.h"
#import <Foundation/Foundation.h>
#import <signal.h>
#import <execinfo.h>
#import <sys/time.h>
#import <string.h>
#import <stdio.h>

static FILE* g_traceFile = NULL;

static void OpenLog(void) {
    if (g_traceFile) return;
    @try {
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* dir = paths.count > 0 ? paths[0] : nil;
        if (!dir) dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        if (!dir) return;
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString* path = [dir stringByAppendingPathComponent:@"apptrace.log"];
        const char* cpath = [path UTF8String];
        if (cpath) {
            g_traceFile = fopen(cpath, "a");
            if (g_traceFile) setvbuf(g_traceFile, NULL, _IONBF, 0);
        }
    } @catch (id ex) {}
}

void CHEAT_LOG_OPEN(void) { OpenLog(); }

void CHEAT_LOG(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    NSLog(@"[StandoffCheat] %s", buf);

    if (!g_traceFile) OpenLog();
    if (g_traceFile) {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        fprintf(g_traceFile, "[%ld.%03d] %s\n", (long)tv.tv_sec, (int)(tv.tv_usec / 1000), buf);
        fflush(g_traceFile);
    }
}

static void CrashHandler(int sig, siginfo_t* info, void* uctx) {
    if (!g_traceFile) OpenLog();
    if (g_traceFile) {
        fprintf(g_traceFile, "\n!!! CRASH signal=%d addr=%p !!!\n", sig, info->si_addr);
        void* stack[64];
        int n = backtrace(stack, 64);
        char** syms = backtrace_symbols(stack, n);
        if (syms) {
            for (int i = 0; i < n; i++) fprintf(g_traceFile, "#%02d %s\n", i, syms[i]);
            free(syms);
        }
        fprintf(g_traceFile, "!!! end crash !!!\n");
        fflush(g_traceFile);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

void CHEAT_INSTALL_CRASH_HANDLERS(void) {
    // Disabled: Unity IL2CPP internally traps SIGSEGV for NullReferenceException handling.
    // Intercepting SIGSEGV causes Unity to terminate on normal startup null checks.
}