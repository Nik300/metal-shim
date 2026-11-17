#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
int main(int argc,char**argv){
  dlopen(argv[1],RTLD_NOW);
  for(uint32_t i=0;i<_dyld_image_count();i++){ const char*n=_dyld_get_image_name(i); if(!strstr(n,argv[2])) continue;
    const struct mach_header_64*h=(const void*)_dyld_get_image_header(i); unsigned long sz;
    const char*sects[]={"__cstring","__oslogstring","text_env"};
    for(int s=0;s<3;s++){ char*p=(char*)getsectiondata(h,"__TEXT",sects[s],&sz); if(!p) continue;
      for(unsigned long o=0;o<sz;){ size_t l=strnlen(p+o,sz-o); if(l>=4) printf("%s\n",p+o); o+=l+1; } }
    break; }
  return 0; }
