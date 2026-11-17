// Experiment: extract AIR bitcode from an MTLFunction and parse it with the system libLLVM.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "TSMetal.h"
typedef void *Ctx, *Buf, *Mod;
int main(int argc, char **argv){ @autoreleasepool{
  id<MTLDevice> d = TSMtlCreateDevice();
  NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
    "struct VIn { float2 pos [[attribute(0)]]; float4 color [[attribute(1)]]; };\n"
    "struct VOut { float4 pos [[position]]; float4 color; float2 uv; };\n"
    "struct U { float4 tint; float depth; };\n"
    "vertex VOut vs_depth(VIn in [[stage_in]], constant U &u [[buffer(1)]]) { VOut o; o.pos = float4(in.pos, u.depth, 1); o.color = 0; o.uv = 0; return o; }\n"
    "fragment float4 fs_tex(VOut in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) { return t.sample(s, in.uv) * in.color; }\n";
  NSError *e; id<MTLLibrary> lib = [d newLibraryWithSource:src options:nil error:&e];
  for (NSString *name in @[@"vs_depth", @"fs_tex"]) {
    id f = [lib newFunctionWithName:name];
    id bc = [f performSelector:@selector(bitcodeData)];
    NSLog(@"%@: bitcodeData class=%@ len=%lu", name, [bc class], (unsigned long)[(NSData*)bc length]);
    NSData *data = (NSData *)bc;
    const uint8_t *b = data.bytes; printf("  magic %02x %02x %02x %02x\n", b[0], b[1], b[2], b[3]);
    void *h = dlopen("/System/Library/PrivateFrameworks/GPUCompiler.framework/Versions/32023/Libraries/libLLVM.dylib", RTLD_NOW|RTLD_LOCAL);
    if (!h) { printf("dlopen: %s\n", dlerror()); return 1; }
    Ctx (*ctxCreate)(void) = dlsym(h, "LLVMContextCreate");
    Buf (*mkbuf)(const char*, size_t, const char*, int) = dlsym(h, "LLVMCreateMemoryBufferWithMemoryRange");
    int (*parse)(Ctx, Buf, Mod*) = dlsym(h, "LLVMParseBitcodeInContext2");
    char *(*print)(Mod) = dlsym(h, "LLVMPrintModuleToString");
    Mod m = NULL; Ctx c = ctxCreate();
    int rc = parse(c, mkbuf(data.bytes, data.length, "air", 0), &m);
    printf("  parse rc=%d module=%p\n", rc, m);
    if (m) { char *s = print(m); NSString *out=[NSString stringWithFormat:@"%@.ll", name]; [@(s) writeToFile:out atomically:YES encoding:NSUTF8StringEncoding error:nil]; printf("  wrote %s (%zu bytes)\n", out.UTF8String, strlen(s)); }
  }
} return 0; }
