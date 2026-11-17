// Lists the methods of an ObjC protocol (required/optional) and whether a given class implements them.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
static void list(Protocol *p, Class c, BOOL req, BOOL inst){
  unsigned n; struct objc_method_description *d = protocol_copyMethodDescriptionList(p, req, inst, &n);
  for(unsigned i=0;i<n;i++){
    BOOL has = inst ? class_respondsToSelector(c, d[i].name) : class_respondsToSelector(object_getClass(c), d[i].name);
    printf("%s %s %c%s  %s\n", has?"IMPL":"----", req?"req":"opt", inst?'-':'+', sel_getName(d[i].name), d[i].types);
  } free(d);
}
int main(int argc, char **argv){ @autoreleasepool{
  dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOW);
  Protocol *p = objc_getProtocol(argv[1]); Class c = objc_getClass(argv[2]);
  if(!p||!c){printf("missing %p %p\n",p,c);return 1;}
  list(p,c,YES,YES); list(p,c,NO,YES); list(p,c,YES,NO); list(p,c,NO,NO);
} return 0; }
