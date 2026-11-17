// glsize: driver cost of real translated fragment shaders (from the shim's GLSL cache) as a function of their text.
// For each file: compile (VS+FS), link, warm-up draw (the deferred hardware compile), for the original text and for a
// minified one (comments/indentation/blank space removed). A unique comment per run defeats any source-keyed cache.
//   glsize <out.tsv> <cache.plist>...
#define GL_SILENCE_DEPRECATION 1
#import <Foundation/Foundation.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl3.h>

static double now(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e6; }
static int runId;
static GLuint zeroUBO;   // 64 KB of zeros behind every uniform block (an unbound block crashes the driver)

static GLuint compile(GLenum type, NSString *src, BOOL *ok) {
    GLuint s = glCreateShader(type);
    const char *c = src.UTF8String;
    glShaderSource(s, 1, &c, NULL);
    glCompileShader(s);
    GLint st = 0; glGetShaderiv(s, GL_COMPILE_STATUS, &st);
    if (!st) { char log[512] = {0}; glGetShaderInfoLog(s, sizeof log, NULL, log); fprintf(stderr, "compile: %.200s\n", log); }
    *ok &= st != 0;
    return s;
}

static NSString *minify(NSString *g) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *raw in [g componentsSeparatedByString:@"\n"]) {
        NSString *l = raw;
        NSRange c = [l rangeOfString:@"//"];
        if (c.location != NSNotFound) l = [l substringToIndex:c.location];
        l = [l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!l.length) continue;
        if ([l hasPrefix:@"#"]) { [out addObject:[@"\n" stringByAppendingString:[l stringByAppendingString:@"\n"]]]; continue; }
        [out addObject:l];
    }
    NSString *s = [out componentsJoinedByString:@""];
    while ([s containsString:@"\n\n"]) s = [s stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n"];
    return s;
}

// Vertex shader writing every varying the fragment shader reads.
static NSString *vertexFor(NSString *fs) {
    NSMutableString *vs = [NSMutableString stringWithString:@"#version 410 core\n"];
    NSMutableString *body = [NSMutableString string];
    NSMutableSet *seen = [NSMutableSet set];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^((?:flat |noperspective |centroid )*)in (\\w+) (\\w+);"
                                                                        options:NSRegularExpressionAnchorsMatchLines error:nil];
    for (NSTextCheckingResult *m in [re matchesInString:fs options:0 range:NSMakeRange(0, fs.length)]) {
        NSString *q = [fs substringWithRange:[m rangeAtIndex:1]], *t = [fs substringWithRange:[m rangeAtIndex:2]],
                 *n = [fs substringWithRange:[m rangeAtIndex:3]];
        if ([seen containsObject:n]) continue;
        [seen addObject:n];
        [vs appendFormat:@"%@out %@ %@;\n", q, t, n];
        [body appendFormat:@"  %@ = %@(0);\n", n, t];
    }
    [vs appendString:@"uniform float ts_clip;\n"];
    [vs appendFormat:@"void main() {\n%@  gl_Position = vec4(ts_clip, 0.0, 0.0, 1.0);\n  gl_PointSize = 1.0;\n}\n", body];
    return vs;
}

// One measurement: compile, link, bind every sampler to its own unit, draw one point into a 1x1 target, glFinish.
static BOOL measure(NSString *fsText, NSString *varyingsFrom, double *tc, double *tl, double *tw) {
    NSString *tag = [NSString stringWithFormat:@"// run %d\n", ++runId];
    NSString *fs = [NSString stringWithFormat:@"#version 410 core\n%@%@", tag, fsText];
    NSString *vs = [vertexFor(varyingsFrom) stringByAppendingString:tag];
    BOOL ok = YES;
    double t0 = now();
    GLuint v = compile(GL_VERTEX_SHADER, vs, &ok), f = compile(GL_FRAGMENT_SHADER, fs, &ok);
    double t1 = now();
    if (!ok) return NO;
    GLuint p = glCreateProgram();
    glAttachShader(p, v); glAttachShader(p, f);
    glLinkProgram(p);
    GLint st = 0; glGetProgramiv(p, GL_LINK_STATUS, &st);
    double t2 = now();
    if (!st) { char log[512] = {0}; glGetProgramInfoLog(p, sizeof log, NULL, log); fprintf(stderr, "link: %.200s\n", log); return NO; }
    glUseProgram(p);
    GLint n = 0; glGetProgramiv(p, GL_ACTIVE_UNIFORMS, &n);
    int unit = 0;
    for (GLint i = 0; i < n; i++) {
        char name[256]; GLint size; GLenum type;
        glGetActiveUniform(p, i, sizeof name, NULL, &size, &type, name);
        BOOL sampler = (type >= GL_SAMPLER_1D && type <= GL_SAMPLER_2D_SHADOW) || (type >= GL_SAMPLER_1D_ARRAY && type <= GL_UNSIGNED_INT_SAMPLER_BUFFER) ||
                       type == GL_SAMPLER_2D_RECT || type == GL_SAMPLER_2D_RECT_SHADOW || type == GL_INT_SAMPLER_2D_RECT ||
                       type == GL_UNSIGNED_INT_SAMPLER_2D_RECT || type == GL_SAMPLER_BUFFER;
        if (sampler) glUniform1i(glGetUniformLocation(p, name), unit++);
    }
    GLint nb = 0; glGetProgramiv(p, GL_ACTIVE_UNIFORM_BLOCKS, &nb);
    for (GLint i = 0; i < nb; i++) { glUniformBlockBinding(p, i, i); glBindBufferBase(GL_UNIFORM_BUFFER, i, zeroUBO); }
    // The point lies outside the clip volume: the driver validates and compiles the pipeline, the fragment shader never
    // runs (with zero-filled buffers a loop could otherwise spin on the GPU until the watchdog).
    glUniform1f(glGetUniformLocation(p, "ts_clip"), 4.0f);
    glDrawArrays(GL_POINTS, 0, 1);
    glFinish();
    double t3 = now();
    if (getenv("GLSIZE_CHECK")) {   // second draw, visible: small if the clipped draw already compiled everything
        glUniform1f(glGetUniformLocation(p, "ts_clip"), 0.0f);
        double a = now(); glDrawArrays(GL_POINTS, 0, 1); glFinish();
        fprintf(stderr, "check: clipped %.2f ms, visible %.2f ms\n", t3 - t2, now() - a);
    }
    GLenum err = glGetError();
    glUseProgram(0); glDeleteProgram(p); glDeleteShader(v); glDeleteShader(f);
    *tc = t1 - t0; *tl = t2 - t1; *tw = t3 - t2;
    if (err) fprintf(stderr, "draw error 0x%x\n", err);
    return err == 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        CGLPixelFormatAttribute a[] = { kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core, kCGLPFAAccelerated, 0 };
        CGLPixelFormatObj pf; GLint npf; CGLContextObj ctx;
        CGLChoosePixelFormat(a, &pf, &npf); CGLCreateContext(pf, NULL, &ctx); CGLSetCurrentContext(ctx);
        GLuint fbo, rb, vao;
        glGenFramebuffers(1, &fbo); glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glGenRenderbuffers(1, &rb); glBindRenderbuffer(GL_RENDERBUFFER, rb);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, 1, 1);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
        glGenVertexArrays(1, &vao); glBindVertexArray(vao);
        glGenBuffers(1, &zeroUBO); glBindBuffer(GL_UNIFORM_BUFFER, zeroUBO);
        void *zeros = calloc(1, 65536); glBufferData(GL_UNIFORM_BUFFER, 65536, zeros, GL_STATIC_DRAW); free(zeros);
        glViewport(0, 0, 1, 1); glEnable(GL_PROGRAM_POINT_SIZE);
        FILE *out = fopen(argv[1], "w");
        fprintf(out, "file\tbytes\tmin_bytes\tlines\tcompile\tlink\twarm\tm_compile\tm_link\tm_warm\n");
        for (int i = 2; i < argc; i++) {
            NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@(argv[i])];
            NSString *g = d[@"glsl"];
            if (!g || [g containsString:@"gl_Position"]) continue;   // fragment shaders only
            NSString *m = minify(g);
            double c, l, w, mc, ml, mw;
            // Order alternates so neither variant always runs first.
            BOOL ok = (i & 1) ? (measure(g, g, &c, &l, &w) && measure(m, g, &mc, &ml, &mw)) : (measure(m, g, &mc, &ml, &mw) && measure(g, g, &c, &l, &w));
            if (!ok) { fprintf(stderr, "skip %s\n", argv[i]); continue; }
            fprintf(out, "%s\t%lu\t%lu\t%lu\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\n", [@(argv[i]) lastPathComponent].UTF8String,
                    (unsigned long)g.length, (unsigned long)m.length, (unsigned long)[g componentsSeparatedByString:@"\n"].count, c, l, w, mc, ml, mw);
            fflush(out);
        }
        fclose(out);
    }
    return 0;
}
