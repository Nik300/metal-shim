#define GL_SILENCE_DEPRECATION 1
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl3.h>
#import <OpenGL/gl3ext.h>
#include <stdio.h>
#include <string.h>
int main(void){
  CGLPixelFormatAttribute a[]={kCGLPFAOpenGLProfile,(CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,kCGLPFAAccelerated,0};
  CGLPixelFormatObj pf; GLint n; CGLChoosePixelFormat(a,&pf,&n); CGLContextObj c; CGLCreateContext(pf,0,&c); CGLSetCurrentContext(c);
  printf("%s | %s\n", glGetString(GL_VERSION), glGetString(GL_SHADING_LANGUAGE_VERSION));
  struct {GLenum e; const char*n;} q[]={{GL_MAX_UNIFORM_BUFFER_BINDINGS,"UBO bindings"},{GL_MAX_VERTEX_UNIFORM_BLOCKS,"VS blocks"},{GL_MAX_FRAGMENT_UNIFORM_BLOCKS,"FS blocks"},{GL_MAX_UNIFORM_BLOCK_SIZE,"block size"},{GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT,"UBO align"},{GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS,"tex units"},{GL_MAX_TEXTURE_IMAGE_UNITS,"FS tex"},{GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS,"VS tex"},{GL_MAX_SAMPLES,"samples"},{GL_MAX_COLOR_ATTACHMENTS,"color att"},{GL_MAX_DRAW_BUFFERS,"draw buffers"},{GL_MAX_DUAL_SOURCE_DRAW_BUFFERS,"dual src"},{GL_MAX_VIEWPORTS,"viewports"},{GL_MAX_TEXTURE_BUFFER_SIZE,"texbuf"},{GL_MAX_VERTEX_ATTRIBS,"attribs"},{GL_MAX_VARYING_COMPONENTS,"varyings"},{GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT,"aniso"}};
  for(unsigned i=0;i<sizeof q/sizeof q[0];i++){GLint v=-1; glGetIntegerv(q[i].e,&v); printf("%s=%d  ",q[i].n,v);} printf("\n");
  GLint ne; glGetIntegerv(GL_NUM_EXTENSIONS,&ne); for(int i=0;i<ne;i++) printf("%s ", glGetStringi(GL_EXTENSIONS,i)); printf("\n");
  return 0;}
