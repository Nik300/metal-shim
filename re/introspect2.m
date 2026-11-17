// Like introspect, but also prints type encodings and ivars (name, type, offset).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
int main(int argc, char **argv){ @autoreleasepool{
  dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOW);
  dlopen("/System/Library/Extensions/AppleParavirtGPUMetal.bundle/Contents/MacOS/AppleParavirtGPUMetal", RTLD_NOW);
  Class c = objc_getClass(argv[1]); if(!c) return 1;
  const char *flt = argc>2 ? argv[2] : NULL;
  printf("## %s size=%zu\n", argv[1], class_getInstanceSize(c));
  unsigned n; Ivar *iv = class_copyIvarList(c, &n);
  for(unsigned i=0;i<n;i++) printf("  ivar %4td %s %s\n", ivar_getOffset(iv[i]), ivar_getName(iv[i]), ivar_getTypeEncoding(iv[i]));
  free(iv);
  for(int inst=0; inst<2; inst++){
    Method *m = class_copyMethodList(inst? c : object_getClass(c), &n);
    for(unsigned i=0;i<n;i++){ const char *s = sel_getName(method_getName(m[i])); if(!flt || strstr(s,flt)) printf("  %c%s  %s\n", inst?'-':'+', s, method_getTypeEncoding(m[i]));}
    free(m);
  }
} return 0; }
