#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
static void dump(const char *name, BOOL inst, const char *filter){
  Class c = objc_getClass(name); if(!c){printf("## %s: non trovata\n",name);return;}
  printf("## %s", name); for(Class s=class_getSuperclass(c); s; s=class_getSuperclass(s)) printf(" : %s", class_getName(s)); printf("\n");
  unsigned n; Method *m = class_copyMethodList(inst? c : object_getClass(c), &n);
  for(unsigned i=0;i<n;i++){ const char *s = sel_getName(method_getName(m[i])); if(!filter || strstr(s,filter)) printf("  %c%s\n", inst?'-':'+', s);} free(m);
}
int main(int argc, char **argv){ @autoreleasepool{
  dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOW);
  void *h = dlopen("/System/Library/Extensions/AppleParavirtGPUMetal.bundle/Contents/MacOS/AppleParavirtGPUMetal", RTLD_NOW);
  printf("paravirt dlopen: %s\n", h ? "ok" : dlerror());
  const char *cls = argc>1 ? argv[1] : "MTLIOAccelDevice"; const char *flt = argc>2 ? argv[2] : NULL;
  dump(cls, NO, flt); dump(cls, YES, flt);
} return 0; }
