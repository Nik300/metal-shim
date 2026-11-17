// Lab-only GL spy for the Moraea glass (TeraScale Glass phase 1). CoreAnimation's OGL renderer calls GL through
// the CGL context's dispatch table (CGLMacro style), so the spy wraps entries of that table for every context the
// lab creates: shader sources, links, uniform uploads, texture binds and draws go to $GLSPY_DIR/glspy.log.
// Never loaded outside the lab.
// Usage: DYLD_INSERT_LIBRARIES=exp/glspy/libglspy.dylib GLSPY_DIR=<dir> CAGLASS_OGL=1 <lab>/WindowServer out.png glass
#include <OpenGL/OpenGL.h>
#include <OpenGL/CGLContext.h>
#include <OpenGL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <dlfcn.h>
#include <ApplicationServices/ApplicationServices.h>
#define HN(p) ((unsigned)(uintptr_t)(p))

#define INTERPOSE(rep, orig) __attribute__((used)) static struct { const void *r, *o; } _ip_##orig \
    __attribute__((section("__DATA,__interpose"))) = { (const void *)rep, (const void *)orig }

static FILE *logf_;
static FILE *L(void) {
    if (!logf_) {
        char p[1024]; snprintf(p, sizeof p, "%s/glspy.log", getenv("GLSPY_DIR") ?: "/tmp");
        logf_ = fopen(p, "w"); setvbuf(logf_, NULL, _IOLBF, 0);
    }
    return logf_;
}
static GLIFunctionDispatch O;   // original entries (one table: the lab has one renderer context)
static int nsrc;
static GLuint cur;
static GLint vpw, vph;
static GLuint curfb;

static void w_shader_source(GLIContext c, GLhandleARB sh, GLsizei n, const GLcharARB *const *s, const GLint *len) {
    char p[1024]; snprintf(p, sizeof p, "%s/shader-%03d-%u.glsl", getenv("GLSPY_DIR") ?: "/tmp", nsrc++, HN(sh));
    FILE *f = fopen(p, "w");
    for (int i = 0; i < n; i++) { if (len && len[i] >= 0) fwrite(s[i], 1, len[i], f); else fputs(s[i], f); }
    fclose(f);
    fprintf(L(), "source shader=%u parts=%d -> %s\n", HN(sh), n, strrchr(p, '/') + 1);
    O.shader_source_ARB(c, sh, n, s, len);
}
static void w_attach(GLIContext c, GLhandleARB p, GLhandleARB s) { fprintf(L(), "attach prog=%u shader=%u\n", HN(p), HN(s)); O.attach_object_ARB(c, p, s); }
static void w_link(GLIContext c, GLhandleARB p) { fprintf(L(), "link prog=%u\n", HN(p)); O.link_program_ARB(c, p); }
// Vertex arrays: attribute pointers (client memory when no buffer is bound) so draws can print their first vertices.
struct va { GLint size; GLenum type; GLsizei stride; const GLvoid *ptr; } vas[16];
static GLuint arraybuf;
static void w_vap(GLIContext c, GLuint i, GLint sz, GLenum t, GLboolean n, GLsizei st, const GLvoid *p) {
    if (i < 16) vas[i] = (struct va){ sz, t, st, arraybuf ? NULL : p };
    O.vertex_attrib_pointer_ARB(c, i, sz, t, n, st, p);
}
static void w_bab(GLIContext c, GLenum t, GLuint b) { if (t == GL_ARRAY_BUFFER) arraybuf = b; O.bind_buffer(c, t, b); }
static void w_bal(GLIContext c, GLhandleARB p, GLuint i, const GLcharARB *n) { fprintf(L(), "attrib prog=%u %s=%u\n", HN(p), n, i); O.bind_attrib_location_ARB(c, p, i, n); }
static int nverts;
static void printverts(GLuint lo, GLuint hi) {
    if (nverts++ > 40 || !getenv("GLSPY_VERTS")) return;
    for (int a = 0; a < 4; a++) {
        struct va *v = &vas[a];
        if (!v->ptr || v->type != GL_FLOAT) continue;
        int st = v->stride ? v->stride : v->size * 4;
        fprintf(L(), "  attr%d:", a);
        for (GLuint k = lo; k <= hi && k < lo + 16; k++) {
            const float *f = (const float *)((const char *)v->ptr + st * k);
            fprintf(L(), " (");
            for (int j = 0; j < v->size; j++) fprintf(L(), "%s%.1f", j ? "," : "", f[j]);
            fprintf(L(), ")");
        }
        fputc('\n', L());
    }
}
static void dumpfb(GLIContext c);
static CGLContextObj sctx;
static void w_da(GLIContext c, GLenum m, GLint f, GLsizei n);
static void w_de(GLIContext c, GLenum m, GLsizei n, GLenum t, const GLvoid *i);
static void w_dre(GLIContext c, GLenum m, GLuint s, GLuint e, GLsizei n, GLenum t, const GLvoid *i);
// GLEngine swaps the draw slots when state changes (…_ACC_Exec variants): wrap them again at every program change.
static void rehook(void) {
    GLIFunctionDispatch *d = &sctx->disp;
    // Only re-wrap GLEngine's own entries: Moraea's CG9M_GLDraw* call whatever they saved, so wrapping them
    // again would loop through us.
    Dl_info di;
#define FROMGLE(f) (dladdr((void *)(f), &di) && di.dli_fname && strstr(di.dli_fname, "GLEngine"))
    if (!FROMGLE(d->draw_arrays) || !FROMGLE(d->draw_range_elements)) { static int once; if (!once++) { dladdr((void *)d->draw_range_elements, &di); fprintf(L(), "draw slot owned by %s %s\n", di.dli_fname, di.dli_sname); } return; }
    if (d->draw_arrays != w_da) { O.draw_arrays = d->draw_arrays; d->draw_arrays = w_da; }
    if (d->draw_elements != w_de) { O.draw_elements = d->draw_elements; d->draw_elements = w_de; }
    if (d->draw_range_elements != w_dre) { O.draw_range_elements = d->draw_range_elements; d->draw_range_elements = w_dre; }
}
static void w_use(GLIContext c, GLhandleARB p) {
    if (sctx) rehook(); if (HN(p) != cur) fprintf(L(), "use prog=%u\n", HN(p)); cur = HN(p); O.use_program_object_ARB(c, p); }
static GLint w_loc(GLIContext c, GLhandleARB p, const GLcharARB *n) { GLint r = O.get_uniform_location_ARB(c, p, n); fprintf(L(), "loc prog=%u %s=%d\n", HN(p), n, r); return r; }
static void dumpf(const char *k, GLint loc, GLsizei n, int comps, const GLfloat *v) {
    fprintf(L(), "%s prog=%u loc=%d n=%d:", k, cur, loc, n);
    for (int i = 0; i < n * comps && i < 32 * 4; i++) fprintf(L(), "%s%.5g", i % comps ? "," : " ", v[i]);
    fputc('\n', L());
}
static void w_u4fv(GLIContext c, GLint l, GLsizei n, const GLfloat *v) { dumpf("u4fv", l, n, 4, v); O.uniform4fv_ARB(c, l, n, v); }
static void w_u3fv(GLIContext c, GLint l, GLsizei n, const GLfloat *v) { dumpf("u3fv", l, n, 3, v); O.uniform3fv_ARB(c, l, n, v); }
static void w_u2fv(GLIContext c, GLint l, GLsizei n, const GLfloat *v) { dumpf("u2fv", l, n, 2, v); O.uniform2fv_ARB(c, l, n, v); }
static void w_u1fv(GLIContext c, GLint l, GLsizei n, const GLfloat *v) { dumpf("u1fv", l, n, 1, v); O.uniform1fv_ARB(c, l, n, v); }
static void w_um4(GLIContext c, GLint l, GLsizei n, GLboolean t, const GLfloat *v) { dumpf("um4fv", l, n, 16, v); O.uniform_matrix4fv_ARB(c, l, n, t, v); }
static void w_u1i(GLIContext c, GLint l, GLint v) { fprintf(L(), "u1i prog=%u loc=%d %d\n", cur, l, v); O.uniform1i_ARB(c, l, v); }
static void w_u1f(GLIContext c, GLint l, GLfloat v) { fprintf(L(), "u1f prog=%u loc=%d %g\n", cur, l, v); O.uniform1f_ARB(c, l, v); }
static void w_u2f(GLIContext c, GLint l, GLfloat a, GLfloat b) { fprintf(L(), "u2f prog=%u loc=%d %g,%g\n", cur, l, a, b); O.uniform2f_ARB(c, l, a, b); }
static void w_u4f(GLIContext c, GLint l, GLfloat a, GLfloat b, GLfloat d, GLfloat e) { fprintf(L(), "u4f prog=%u loc=%d %g,%g,%g,%g\n", cur, l, a, b, d, e); O.uniform4f_ARB(c, l, a, b, d, e); }
static GLenum unit;
static void w_active(GLIContext c, GLenum t) { unit = t - GL_TEXTURE0; O.active_texture(c, t); }
static void w_bind(GLIContext c, GLenum t, GLuint tex) { fprintf(L(), "bind unit=%u target=0x%x tex=%u\n", unit, t, tex); O.bind_texture(c, t, tex); }
static void w_da(GLIContext c, GLenum m, GLint f, GLsizei n) { fprintf(L(), "drawArrays fb=%u prog=%u mode=%u first=%d count=%d\n", curfb, cur, m, f, n); O.draw_arrays(c, m, f, n); }
static void w_de(GLIContext c, GLenum m, GLsizei n, GLenum t, const GLvoid *i) { fprintf(L(), "drawElements fb=%u prog=%u mode=%u count=%d\n", curfb, cur, m, n); O.draw_elements(c, m, n, t, i); }
static void w_dre(GLIContext c, GLenum m, GLuint s, GLuint e, GLsizei n, GLenum t, const GLvoid *i) { fprintf(L(), "drawRange fb=%u prog=%u mode=%u count=%d range=%u..%u\n", curfb, cur, m, n, s, e); printverts(s, e); O.draw_range_elements(c, m, s, e, n, t, i);
    // GLSPY_DUMPAFTER=<prog>:<n>: read back the current framebuffer right after the n-th draw of that program.
    static int dprog = -1, dn, seen;
    if (dprog < 0) { dprog = 0; if (getenv("GLSPY_DUMPAFTER")) sscanf(getenv("GLSPY_DUMPAFTER"), "%d:%d", &dprog, &dn); }
    if ((GLuint)dprog == cur && seen + 1 == dn) {   // GL state of that draw
        GLint sb[4], bs, bd, st, cm[4] = {0}, pr; GLboolean wm[4];
        O.get_integerv(c, GL_SCISSOR_BOX, sb); O.get_integerv(c, GL_BLEND_SRC, &bs); O.get_integerv(c, GL_BLEND_DST, &bd);
        O.get_booleanv(c, GL_COLOR_WRITEMASK, wm); O.get_integerv(c, GL_CURRENT_PROGRAM, &pr);
        fprintf(L(), "state: scissor %d %d,%d %dx%d blend %d 0x%x/0x%x mask %d%d%d%d stencil %d depth %d alphatest %d cull %d prog %d\n",
                O.is_enabled(c, GL_SCISSOR_TEST), sb[0], sb[1], sb[2], sb[3], O.is_enabled(c, GL_BLEND), bs, bd, wm[0], wm[1], wm[2], wm[3],
                O.is_enabled(c, GL_STENCIL_TEST), O.is_enabled(c, GL_DEPTH_TEST), O.is_enabled(c, GL_ALPHA_TEST), O.is_enabled(c, GL_CULL_FACE), pr);
        GLint au; O.get_integerv(c, GL_ACTIVE_TEXTURE, &au);
        for (int u = 0; u < 4; u++) {
            GLint t2 = 0, tr = 0; O.active_texture(c, GL_TEXTURE0 + u);
            O.get_integerv(c, GL_TEXTURE_BINDING_2D, &t2); O.get_integerv(c, GL_TEXTURE_BINDING_RECTANGLE_ARB, &tr);
            fprintf(L(), "  unit %d: 2D %d rect %d\n", u, t2, tr);
        }
        O.active_texture(c, au);
        const char *names[] = { "texture0", "texture1", "cg9m_mipT", "cg9m_sgT" };
        for (int k = 0; k < 4; k++) {
            GLint loc = O.get_uniform_location_ARB(c, (GLhandleARB)(uintptr_t)pr, names[k]), v = -1;
            if (loc >= 0) O.get_uniformiv_ARB(c, (GLhandleARB)(uintptr_t)pr, loc, &v);
            fprintf(L(), "  sampler %s loc %d unit %d\n", names[k], loc, v);
        }
        (void)st; (void)cm;
    }
    if ((GLuint)dprog == cur && ++seen == dn) { fprintf(L(), "dump after draw %d of prog %u\n", dn, cur); dumpfb(c); }
}
static void w_vp(GLIContext c, GLint x, GLint y, GLsizei w, GLsizei h) { vpw = w; vph = h; fprintf(L(), "viewport %d,%d %dx%d\n", x, y, w, h); O.viewport(c, x, y, w, h); }
// GLSPY_FBDUMP=1: before switching framebuffer, the one being left is read back (current viewport) to fb-NNN-<fbo>.png.
static int ndump;
static void dumpfb(GLIContext c) {
    if (!getenv("GLSPY_FBDUMP") || vpw <= 0 || vph <= 0 || ndump > 400) return;
    size_t W = vpw, H = vph; unsigned char *px = malloc(W * H * 4);
    O.read_pixels(c, 0, 0, vpw, vph, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, px);
    char p[1024]; snprintf(p, sizeof p, "%s/fb-%03d-%u.png", getenv("GLSPY_DIR") ?: "/tmp", ndump++, curfb);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef bc = CGBitmapContextCreate(px, W, H, 8, W * 4, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGImageRef img = CGBitmapContextCreateImage(bc);
    CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)p, strlen(p), false);
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(u, CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(dst, img, NULL); CGImageDestinationFinalize(dst);
    CFRelease(dst); CFRelease(u); CGImageRelease(img); CGContextRelease(bc); CGColorSpaceRelease(cs); free(px);
    fprintf(L(), "dumped %s %zux%zu\n", strrchr(p, '/') + 1, W, H);
}
static void w_bfb(GLIContext c, GLenum t, GLuint f) {
    if (f != curfb) dumpfb(c);
    fprintf(L(), "bindFB 0x%x %u\n", t, f); curfb = f; O.bind_framebuffer_EXT(c, t, f);
}
static void w_cts(GLIContext c, GLenum t, GLint l, GLint xo, GLint yo, GLint x, GLint y, GLsizei w, GLsizei h) { fprintf(L(), "copyTexSub level=%d %d,%d <- %d,%d %dx%d\n", l, xo, yo, x, y, w, h); O.copy_tex_sub_image2D(c, t, l, xo, yo, x, y, w, h); }
static void w_ti2(GLIContext c, GLenum t, GLint l, GLenum i, GLsizei w, GLsizei h, GLint b, GLenum f, GLenum ty, const GLvoid *p) { fprintf(L(), "texImage2D 0x%x level=%d ifmt=0x%x %dx%d\n", t, l, i, w, h); O.tex_image2D(c, t, l, i, w, h, b, f, ty, p); }
static void w_mip(GLIContext c, GLenum t) { fprintf(L(), "generateMipmap 0x%x\n", t); O.generate_mipmap_EXT(c, t); }

static void w_begin(GLIContext c, GLenum m) { fprintf(L(), "begin prog=%u mode=%u\n", cur, m); O.begin(c, m); }
static void w_dea(GLIContext c, GLenum m, GLint f, GLsizei n) { fprintf(L(), "drawElemArrayAPPLE prog=%u mode=%u count=%d\n", cur, m, n); O.draw_element_array_APPLE(c, m, f, n); }
static void w_drea(GLIContext c, GLenum m, GLuint s, GLuint e, GLint f, GLsizei n) { fprintf(L(), "drawRangeElemArrayAPPLE prog=%u mode=%u count=%d\n", cur, m, n); O.draw_range_element_array_APPLE(c, m, s, e, f, n); }
static void w_mda(GLIContext c, GLenum m, const GLint *f, const GLsizei *n, GLsizei k) { fprintf(L(), "multiDrawArrays prog=%u mode=%u k=%d\n", cur, m, k); O.multi_draw_arrays(c, m, f, n, k); }


// GLSPY_ALL=1: every slot of the table goes through a counting stub first (stubs.s); counts per slot name at exit.
void *glspy_orig[1400];
static unsigned long counts[1400];
extern char glspy_stubs[];
void glspy_count(unsigned long i) { counts[i]++; }
static CGLContextObj hctx;
static void dumpcounts(void) {
    FILE *f = L();
    { void **t = (void **)&hctx->disp; int lost = 0; for (int i = 0; i < 974; i++) if (glspy_orig[i] && t[i] != glspy_stubs + 16 * i) { Dl_info di; dladdr(t[i], &di); if (lost++ < 20) fprintf(f, "replaced slot %d -> %s %s\n", i, di.dli_fname ? strrchr(di.dli_fname, '/') : "?", di.dli_sname ?: "?"); } fprintf(f, "replaced %d slots\n", lost); }
    for (int i = 0; i < 1400; i++) if (counts[i]) fprintf(f, "slot %d %lu\n", i, counts[i]);
}
static void hookall(GLIFunctionDispatch *d) {
    void **t = (void **)d;
    size_t n = sizeof(*d) / sizeof(void *);
    size_t k = 0;
    for (size_t i = 0; i < n && i < 1400; i++) {   // only real GL entry points (the table may be shorter than the SDK's)
        Dl_info di;
        if (!t[i] || !dladdr(t[i], &di) || !di.dli_fname || !di.dli_sname) continue;   // code with a symbol, not data
        glspy_orig[i] = t[i]; t[i] = glspy_stubs + 16 * i; k++;
    }
    n = k;
    atexit(dumpcounts);
    fprintf(L(), "all %zu slots counted\n", n);
}

static void hook(CGLContextObj ctx) {
    GLIFunctionDispatch *d = &ctx->disp;
    sctx = ctx;
    if (getenv("GLSPY_ALL")) { hctx = ctx; hookall(d); return; }
    O = *d;
#define W(e, f) d->e = f
    W(shader_source_ARB, w_shader_source); W(attach_object_ARB, w_attach); W(link_program_ARB, w_link);
    W(use_program_object_ARB, w_use); W(get_uniform_location_ARB, w_loc);
    W(uniform4fv_ARB, w_u4fv); W(uniform3fv_ARB, w_u3fv); W(uniform2fv_ARB, w_u2fv); W(uniform1fv_ARB, w_u1fv);
    W(uniform_matrix4fv_ARB, w_um4); W(uniform1i_ARB, w_u1i); W(uniform1f_ARB, w_u1f); W(uniform2f_ARB, w_u2f); W(uniform4f_ARB, w_u4f);
    W(active_texture, w_active); W(bind_texture, w_bind);
    W(draw_arrays, w_da); W(draw_elements, w_de); W(draw_range_elements, w_dre);
    W(viewport, w_vp); W(bind_framebuffer_EXT, w_bfb); W(copy_tex_sub_image2D, w_cts); W(tex_image2D, w_ti2);
    W(generate_mipmap_EXT, w_mip);
    W(vertex_attrib_pointer_ARB, w_vap); W(bind_buffer, w_bab); W(bind_attrib_location_ARB, w_bal);
    W(begin, w_begin); W(draw_element_array_APPLE, w_dea); W(draw_range_element_array_APPLE, w_drea); W(multi_draw_arrays, w_mda);
    fprintf(L(), "hooked context %p (%s)\n", (void *)ctx, (const char *)O.get_string(ctx->rend, GL_VERSION));
}

static CGLError my_CGLCreateContext(CGLPixelFormatObj pf, CGLContextObj share, CGLContextObj *out) {
    CGLError e = CGLCreateContext(pf, share, out);
    if (!e && *out) hook(*out);
    // TeraScale Glass in the same lab run: its link/use hooks go on top of the spy's.
    void (*tsg)(void *) = (void (*)(void *))dlsym(RTLD_DEFAULT, "TSGlassHookContext");
    if (!e && *out && tsg) tsg(*out);
    return e;
}
INTERPOSE(my_CGLCreateContext, CGLCreateContext);

// Draws issued through the exported libGL symbols instead of the context table.
static void s_da(GLenum m, GLint f, GLsizei n) { fprintf(L(), "SYM drawArrays prog=%u fb=%u mode=%u count=%d\n", cur, curfb, m, n); glDrawArrays(m, f, n); }
INTERPOSE(s_da, glDrawArrays);
static void s_de(GLenum m, GLsizei n, GLenum t, const GLvoid *i) { fprintf(L(), "SYM drawElements prog=%u fb=%u mode=%u count=%d\n", cur, curfb, m, n); glDrawElements(m, n, t, i); }
INTERPOSE(s_de, glDrawElements);
static void s_dre(GLenum m, GLuint a, GLuint b, GLsizei n, GLenum t, const GLvoid *i) { fprintf(L(), "SYM drawRange prog=%u fb=%u mode=%u count=%d\n", cur, curfb, m, n); glDrawRangeElements(m, a, b, n, t, i); }
INTERPOSE(s_dre, glDrawRangeElements);
