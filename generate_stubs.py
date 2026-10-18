import sys
import re

if len(sys.argv) < 4:
    print("Usage: generate_stubs.py orig_syms.txt stubs.mm TargetName")
    sys.exit(1)

syms_file = sys.argv[1]
out_file = sys.argv[2]
target = sys.argv[3]

with open(syms_file, "r", encoding="utf-8", errors="ignore") as f:
    symbols = [line.strip() for line in f if line.strip()]

classes = set()
c_funcs = set()
globals_def = set()

SYSTEM_PREFIXES = (
    "objc_", "dispatch_", "asl_", "Unwind_", "pthread_", "malloc", "free",
    "memcpy", "memset", "NS", "UI", "CA", "CF", "os_log", "getpid",
    "clock_", "mach_", "dyld", "snprintf", "fprintf"
)

for sym in symbols:
    if sym.startswith("_OBJC_CLASS_$_"):
        cls = sym[len("_OBJC_CLASS_$_"):]
        if cls.startswith(("NS", "UI", "CA", "CF")):
            continue
        cls = re.sub(r"[^A-Za-z0-9_]", "_", cls)
        if cls:
            classes.add(cls)
    elif (
        sym.startswith("_OBJC_METACLASS_$_")
        or sym.startswith("_OBJC_IVAR_$_")
        or sym.startswith("_OBJC_INSTANCE_VARIABLES_")
    ):
        continue
    elif sym.startswith("___") or sym in ["_fatal_error", "_FSReadStream"]:
        continue
    elif "VersionNumber" in sym:
        stem = sym.lstrip("_")
        globals_def.add(f'extern "C" __attribute__((used)) double {stem} = 1.0;')
    elif "VersionString" in sym:
        stem = sym.lstrip("_")
        globals_def.add(f'extern "C" __attribute__((used)) const unsigned char {stem}[] = "1.0";')
    else:
        stem = sym.lstrip("_")
        if stem.startswith(SYSTEM_PREFIXES):
            continue
        stem = re.sub(r"[^A-Za-z0-9_]", "_", stem)
        if stem:
            c_funcs.add(f'extern "C" __attribute__((used)) void* {stem}() {{ return 0; }}')

with open(out_file, "w", encoding="utf-8") as f:
    f.write(f"// AUTO-GENERATED symbol-compat stubs for {target}\n")
    f.write("#import <Foundation/Foundation.h>\n\n")
    for g in sorted(globals_def):
        f.write(g + "\n")
    f.write("\n")
    for c in sorted(c_funcs):
        f.write(c + "\n")
    f.write("\n")
    for cls in sorted(classes):
        f.write(f"""@interface {cls} : NSObject
+ (BOOL)resolveClassMethod:(SEL)sel;
+ (BOOL)resolveInstanceMethod:(SEL)sel;
@end
@implementation {cls}
+ (BOOL)resolveClassMethod:(SEL)sel {{ return YES; }}
+ (BOOL)resolveInstanceMethod:(SEL)sel {{ return YES; }}
- (id)forwardingTargetForSelector:(SEL)aSelector {{ return nil; }}
- (void)forwardInvocation:(NSInvocation *)anInvocation {{}}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {{
    return [NSMethodSignature signatureWithObjCTypes:"v@:"];
}}
+ (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {{
    return [NSMethodSignature signatureWithObjCTypes:"v@:"];
}}
+ (void)forwardInvocation:(NSInvocation *)anInvocation {{}}
@end
""")
print(f"Generated {len(classes)} ObjC class stubs, {len(c_funcs)} C functions, {len(globals_def)} globals.")
