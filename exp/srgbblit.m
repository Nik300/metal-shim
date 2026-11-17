// Probe: is glBlitFramebuffer between GL_SRGB8_ALPHA8 and GL_RGBA8 a raw copy when GL_FRAMEBUFFER_SRGB
// is disabled (and when enabled)? Metal copies between sRGB and linear views bit for bit.
#import <Foundation/Foundation.h>
#define GL_SILENCE_DEPRECATION 1
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl3.h>
static GLuint tex(GLenum ifmt, uint32_t texel) {
    GLuint t; glGenTextures(1, &t); glBindTexture(GL_TEXTURE_2D, t);
    uint32_t px[16]; for (int i = 0; i < 16; i++) px[i] = texel;
    glTexImage2D(GL_TEXTURE_2D, 0, ifmt, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
    return t;
}
static uint32_t blit(GLenum sf, GLenum df, BOOL srgbOn) {
    GLuint s = tex(sf, 0xff804020), d = tex(df, 0);
    GLuint fb[2]; glGenFramebuffers(2, fb);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, fb[0]); glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, s, 0);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fb[1]); glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, d, 0);
    if (srgbOn) glEnable(GL_FRAMEBUFFER_SRGB); else glDisable(GL_FRAMEBUFFER_SRGB);
    glBlitFramebuffer(0, 0, 4, 4, 0, 0, 4, 4, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    uint32_t out[16] = {0};
    glBindTexture(GL_TEXTURE_2D, d); glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, out);
    return out[5];
}
int main(void) { @autoreleasepool {
    CGLPixelFormatAttribute a[] = { kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core, kCGLPFAAccelerated, 0 };
    CGLPixelFormatObj pf; GLint n; CGLChoosePixelFormat(a, &pf, &n);
    CGLContextObj ctx; CGLCreateContext(pf, NULL, &ctx); CGLSetCurrentContext(ctx);
    printf("source texel 0xff804020\n");
    for (int on = 0; on < 2; on++) {
        printf("FRAMEBUFFER_SRGB %s: srgb->rgba %08x  rgba->srgb %08x  srgb->srgb %08x  rgba->rgba %08x\n", on ? "on " : "off",
               blit(GL_SRGB8_ALPHA8, GL_RGBA8, on), blit(GL_RGBA8, GL_SRGB8_ALPHA8, on), blit(GL_SRGB8_ALPHA8, GL_SRGB8_ALPHA8, on), blit(GL_RGBA8, GL_RGBA8, on));
    }
} return 0; }
