// Does a texture buffer follow its buffer after glBufferData re-specifies (orphans) the storage?
// Draws column i reading texelFetch(tbo, 0) after writing value i into the buffer, no glFinish between.
#import <Foundation/Foundation.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl3.h>
#define N 64
static GLuint compile(GLenum type, const char *src) {
    GLuint s = glCreateShader(type); glShaderSource(s, 1, &src, NULL); glCompileShader(s);
    GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) { char log[1024]; glGetShaderInfoLog(s, sizeof log, NULL, log); printf("compile: %s\n", log); exit(1); }
    return s;
}
int main(int argc, char **argv) { @autoreleasepool {
    CGLPixelFormatAttribute attrs[] = { kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core, kCGLPFAAccelerated, 0 };
    CGLPixelFormatObj pf; GLint npf; CGLChoosePixelFormat(attrs, &pf, &npf);
    CGLContextObj ctx; CGLCreateContext(pf, NULL, &ctx); CGLSetCurrentContext(ctx);
    printf("renderer: %s\n", glGetString(GL_RENDERER));
    GLuint prog = glCreateProgram();
    glAttachShader(prog, compile(GL_VERTEX_SHADER, "#version 410\nvoid main(){ vec2 p[3]=vec2[](vec2(-1,-1),vec2(3,-1),vec2(-1,3)); gl_Position=vec4(p[gl_VertexID],0,1);}"));
    glAttachShader(prog, compile(GL_FRAGMENT_SHADER, "#version 410\nuniform usamplerBuffer tb; out uvec4 o; void main(){ o=uvec4(texelFetch(tb, 3).r,0,0,1);}"));
    glLinkProgram(prog); glUseProgram(prog);
    GLuint vao; glGenVertexArrays(1, &vao); glBindVertexArray(vao);
    GLuint rb, fbo; glGenTextures(1, &rb); glBindTexture(GL_TEXTURE_2D, rb);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R32UI, N, 1, 0, GL_RED_INTEGER, GL_UNSIGNED_INT, NULL);
    glGenFramebuffers(1, &fbo); glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, rb, 0);
    const char *modes[] = { "glBufferData (orphan), TBO created once", "glBufferSubData, TBO created once",
                            "glBufferData + glTexBuffer again", "glBufferData, size alternating 2048/16388" };
    for (int mode = 0; mode < 4; mode++) {
        GLuint buf, tbo; glGenBuffers(1, &buf); glGenTextures(1, &tbo);
        uint32_t data[4100] = {0};
        glBindBuffer(GL_TEXTURE_BUFFER, buf); glBufferData(GL_TEXTURE_BUFFER, 2048, data, GL_DYNAMIC_DRAW);
        glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_BUFFER, tbo); glTexBuffer(GL_TEXTURE_BUFFER, GL_R32UI, buf);
        glUniform1i(glGetUniformLocation(prog, "tb"), 0);
        GLuint clear[4] = {0}; glClearBufferuiv(GL_COLOR, 0, clear);
        for (int i = 0; i < N; i++) {
            data[3] = 1000 + i;
            glBindBuffer(GL_TEXTURE_BUFFER, buf);
            GLsizeiptr size = mode == 3 && (i & 1) ? 16388 : 2048;
            if (mode == 1) glBufferSubData(GL_TEXTURE_BUFFER, 0, 2048, data);
            else glBufferData(GL_TEXTURE_BUFFER, size, data, GL_DYNAMIC_DRAW);
            if (mode == 2) glTexBuffer(GL_TEXTURE_BUFFER, GL_R32UI, buf);
            glViewport(i, 0, 1, 1);
            glDrawArrays(GL_TRIANGLES, 0, 3);
        }
        uint32_t px[N * 4];
        glReadPixels(0, 0, N, 1, GL_RGBA_INTEGER, GL_UNSIGNED_INT, px);
        int wrong = 0; char sample[256] = ""; size_t at = 0;
        for (int i = 0; i < N; i++) if (px[i * 4] != 1000 + (uint32_t)i) { if (wrong < 6) at += snprintf(sample + at, sizeof sample - at, " col%d=%u", i, px[i * 4]); wrong++; }
        printf("%-45s wrong %2d/%d%s  (err 0x%x)\n", modes[mode], wrong, N, sample, glGetError());
        glDeleteTextures(1, &tbo); glDeleteBuffers(1, &buf);
    }
    return 0;
} }
