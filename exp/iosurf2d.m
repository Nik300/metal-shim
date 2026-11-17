// Probe: does CGLTexImageIOSurface2D accept GL_TEXTURE_RECTANGLE (not only RECTANGLE) on this driver,
// for which formats, and are render + sample through two GL textures of one surface coherent?
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#define GL_SILENCE_DEPRECATION 1
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl3.h>
#import <OpenGL/CGLIOSurface.h>
static IOSurfaceRef mk(int w, int h, int bpe, uint32_t fourcc) {
    return IOSurfaceCreate((__bridge CFDictionaryRef)@{ (id)kIOSurfaceWidth: @(w), (id)kIOSurfaceHeight: @(h),
        (id)kIOSurfaceBytesPerElement: @(bpe), (id)kIOSurfacePixelFormat: @(fourcc) });
}
int main(void) { @autoreleasepool {
    CGLPixelFormatAttribute a[] = { kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core, kCGLPFAAccelerated, 0 };
    CGLPixelFormatObj pf; GLint n; CGLChoosePixelFormat(a, &pf, &n);
    CGLContextObj ctx; CGLCreateContext(pf, NULL, &ctx); CGLSetCurrentContext(ctx);
    struct { const char *name; GLenum ifmt, fmt, type; int bpe; uint32_t cc; } f[] = {
        { "BGRA8", GL_RGBA8, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, 4, 'BGRA' },
        { "RGBA8", GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 4, 'RGBA' },
        { "R8", GL_R8, GL_RED, GL_UNSIGNED_BYTE, 1, 'L008' },
        { "RG8", GL_RG8, GL_RG, GL_UNSIGNED_BYTE, 2, '2C08' },
        { "RGBA16F", GL_RGBA16F, GL_RGBA, GL_HALF_FLOAT, 8, 'RGhA' },
        { "RGB10A2", GL_RGB10_A2, GL_BGRA, GL_UNSIGNED_INT_2_10_10_10_REV, 4, 'l10r' },
    };
    for (int i = 0; i < 6; i++) {
        for (int pot = 0; pot < 2; pot++) {
            int w = pot ? 256 : 300, h = pot ? 256 : 170;
            IOSurfaceRef s = mk(w, h, f[i].bpe, f[i].cc);
            GLuint t; glGenTextures(1, &t); glBindTexture(GL_TEXTURE_RECTANGLE, t);
            CGLError e = CGLTexImageIOSurface2D(ctx, GL_TEXTURE_RECTANGLE, f[i].ifmt, w, h, f[i].fmt, f[i].type, s, 0);
            GLenum ge = glGetError();
            GLuint fb; glGenFramebuffers(1, &fb); glBindFramebuffer(GL_FRAMEBUFFER, fb);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_RECTANGLE, t, 0);
            GLenum st = e ? 0 : glCheckFramebufferStatus(GL_FRAMEBUFFER);
            int coherent = -1;
            if (!e && st == GL_FRAMEBUFFER_COMPLETE && i == 0) {
                // render a clear through texture t, read via a second 2D texture on the same surface
                glViewport(0, 0, w, h); glClearColor(1, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
                GLuint t2; glGenTextures(1, &t2); glBindTexture(GL_TEXTURE_RECTANGLE, t2);
                CGLTexImageIOSurface2D(ctx, GL_TEXTURE_RECTANGLE, f[i].ifmt, w, h, f[i].fmt, f[i].type, s, 0);
                uint32_t px[4] = {0};
                GLuint fb2; glGenFramebuffers(1, &fb2); glBindFramebuffer(GL_READ_FRAMEBUFFER, fb2);
                glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_RECTANGLE, t2, 0);
                glReadPixels(1, 1, 1, 1, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, px);
                coherent = px[0] == 0xffff0000;
                glFinish();
                IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
                uint32_t cpu = *(uint32_t *)IOSurfaceGetBaseAddress(s);
                IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
                printf("   second-texture read 0x%08x, CPU read after glFinish 0x%08x\n", px[0], cpu);
            }
            printf("%-8s %dx%d 2D: cgl=%d glerr=0x%x fbo=0x%x coherent=%d\n", f[i].name, w, h, e, ge, st, coherent);
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            CFRelease(s);
        }
    }
} return 0; }
