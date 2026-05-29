#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_BMP
#define STBI_ONLY_GIF
#define STBI_NO_STDIO
#include "stb_image.h"
#include "image.h"
#include "httputil.h"
#include "base64.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static CachedImage g_img_cache[IMG_CACHE_MAX];
static int g_img_count = 0;
static CRITICAL_SECTION g_img_cs;

void image_init(void) {
    InitializeCriticalSection(&g_img_cs);
    g_img_count = 0;
}

void image_shutdown(void) {
    for (int i = 0; i < g_img_count; i++) {
        if (g_img_cache[i].frame_count > 1) {
            for (int f = 0; f < g_img_cache[i].frame_count; f++)
                if (g_img_cache[i].frames[f]) DeleteObject(g_img_cache[i].frames[f]);
        } else {
            if (g_img_cache[i].hbmp) DeleteObject(g_img_cache[i].hbmp);
        }
    }
    g_img_count = 0;
    DeleteCriticalSection(&g_img_cs);
}

/* Create a pre-multiplied alpha 32-bit HBITMAP from RGBA pixels */
static HBITMAP create_hbitmap_from_rgba(const unsigned char *pixels, int w, int h) {
    BITMAPINFO bmi = {0};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = w;
    bmi.bmiHeader.biHeight = -h; /* top-down */
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    void *bits = NULL;
    HBITMAP hbmp = CreateDIBSection(NULL, &bmi, DIB_RGB_COLORS, &bits, NULL, 0);
    if (!hbmp || !bits) return NULL;

    /* Convert RGBA to pre-multiplied BGRA for AlphaBlend */
    unsigned char *dst = (unsigned char *)bits;
    for (int i = 0; i < w * h; i++) {
        unsigned char r = pixels[i * 4 + 0];
        unsigned char g = pixels[i * 4 + 1];
        unsigned char b = pixels[i * 4 + 2];
        unsigned char a = pixels[i * 4 + 3];
        dst[i * 4 + 0] = (unsigned char)(b * a / 255);
        dst[i * 4 + 1] = (unsigned char)(g * a / 255);
        dst[i * 4 + 2] = (unsigned char)(r * a / 255);
        dst[i * 4 + 3] = a;
    }
    return hbmp;
}

/* Decode image from memory buffer, return HBITMAP */
static HBITMAP decode_image_mem(const unsigned char *data, int len, int req_w, int req_h,
                                int *out_w, int *out_h) {
    int w, h, channels;
    unsigned char *pixels = stbi_load_from_memory(data, len, &w, &h, &channels, 4);
    if (!pixels) return NULL;

    /* Scale to requested size if specified */
    int final_w = (req_w > 0) ? req_w : w;
    int final_h = (req_h > 0) ? req_h : h;

    HBITMAP hbmp;
    if (final_w != w || final_h != h) {
        /* Simple nearest-neighbor resize */
        unsigned char *scaled = (unsigned char *)malloc(final_w * final_h * 4);
        if (!scaled) { stbi_image_free(pixels); return NULL; }
        for (int y = 0; y < final_h; y++) {
            int sy = y * h / final_h;
            for (int x = 0; x < final_w; x++) {
                int sx = x * w / final_w;
                memcpy(&scaled[(y * final_w + x) * 4], &pixels[(sy * w + sx) * 4], 4);
            }
        }
        hbmp = create_hbitmap_from_rgba(scaled, final_w, final_h);
        free(scaled);
    } else {
        hbmp = create_hbitmap_from_rgba(pixels, w, h);
    }

    *out_w = final_w;
    *out_h = final_h;
    stbi_image_free(pixels);
    return hbmp;
}

/* Check cache for existing image */
static CachedImage *cache_find(const char *key) {
    for (int i = 0; i < g_img_count; i++) {
        if (strcmp(g_img_cache[i].key, key) == 0)
            return &g_img_cache[i];
    }
    return NULL;
}

/* Add to cache (evicts oldest if full) */
static CachedImage *cache_add(const char *key, HBITMAP hbmp, int w, int h) {
    CachedImage *slot;
    if (g_img_count >= IMG_CACHE_MAX) {
        /* Evict first entry */
        if (g_img_cache[0].frame_count > 1) {
            for (int f = 0; f < g_img_cache[0].frame_count; f++)
                if (g_img_cache[0].frames[f]) DeleteObject(g_img_cache[0].frames[f]);
        } else {
            if (g_img_cache[0].hbmp) DeleteObject(g_img_cache[0].hbmp);
        }
        memmove(&g_img_cache[0], &g_img_cache[1], sizeof(CachedImage) * (IMG_CACHE_MAX - 1));
        g_img_count = IMG_CACHE_MAX - 1;
    }
    slot = &g_img_cache[g_img_count++];
    memset(slot, 0, sizeof(CachedImage));
    strncpy(slot->key, key, sizeof(slot->key) - 1);
    slot->key[sizeof(slot->key) - 1] = '\0';
    slot->hbmp = hbmp;
    slot->width = w;
    slot->height = h;
    slot->start_tick = GetTickCount();
    return slot;
}

/* Check if data is a GIF (animated or not) */
static int is_gif_data(const unsigned char *data, int len) {
    return (len >= 6 && (memcmp(data, "GIF89a", 6) == 0 || memcmp(data, "GIF87a", 6) == 0));
}

/* Get current frame HBITMAP from an animated cache entry */
static HBITMAP cache_get_current_frame(CachedImage *cached) {
    if (cached->frame_count <= 1) return cached->hbmp;
    DWORD elapsed = GetTickCount() - cached->start_tick;
    /* Calculate total loop duration */
    int total_ms = 0;
    for (int i = 0; i < cached->frame_count; i++)
        total_ms += cached->delays[i] > 0 ? cached->delays[i] : 100;
    if (total_ms <= 0) total_ms = cached->frame_count * 100;
    int pos = (int)(elapsed % (DWORD)total_ms);
    int accum = 0;
    for (int i = 0; i < cached->frame_count; i++) {
        accum += cached->delays[i] > 0 ? cached->delays[i] : 100;
        if (pos < accum) return cached->frames[i];
    }
    return cached->frames[0];
}

/* Decode animated GIF into cache entry. Returns TRUE if successful. */
static BOOL decode_gif_animated(const unsigned char *data, int len, int req_w, int req_h,
                                CachedImage *slot) {
    int *delays = NULL;
    int w, h, frames_z, comp;
    unsigned char *pixels = stbi_load_gif_from_memory(data, len, &delays, &w, &h, &frames_z, &comp, 4);
    if (!pixels) return FALSE;
    if (frames_z <= 0) { stbi_image_free(pixels); if (delays) stbi_image_free(delays); return FALSE; }

    int final_w = (req_w > 0) ? req_w : w;
    int final_h = (req_h > 0) ? req_h : h;
    int count = frames_z > IMG_MAX_FRAMES ? IMG_MAX_FRAMES : frames_z;

    for (int i = 0; i < count; i++) {
        unsigned char *frame_pixels = pixels + (size_t)i * w * h * 4;
        HBITMAP hbmp;
        if (final_w != w || final_h != h) {
            unsigned char *scaled = (unsigned char *)malloc(final_w * final_h * 4);
            if (!scaled) { hbmp = NULL; } else {
                for (int y = 0; y < final_h; y++) {
                    int sy = y * h / final_h;
                    for (int x = 0; x < final_w; x++) {
                        int sx = x * w / final_w;
                        memcpy(&scaled[(y * final_w + x) * 4], &frame_pixels[(sy * w + sx) * 4], 4);
                    }
                }
                hbmp = create_hbitmap_from_rgba(scaled, final_w, final_h);
                free(scaled);
            }
        } else {
            hbmp = create_hbitmap_from_rgba(frame_pixels, w, h);
        }
        slot->frames[i] = hbmp;
        slot->delays[i] = delays ? delays[i] : 100;
    }
    slot->frame_count = count;
    slot->hbmp = slot->frames[0];
    slot->width = final_w;
    slot->height = final_h;
    slot->start_tick = GetTickCount();

    stbi_image_free(pixels);
    if (delays) stbi_image_free(delays);
    return TRUE;
}

/* Build a cache key from source + dimensions */
static void make_cache_key(const char *source, int req_w, int req_h, char *key, int key_size) {
    snprintf(key, key_size, "%s|%d|%d", source, req_w, req_h);
}

/* Load file into memory buffer */
static unsigned char *load_file_mem(const char *path, int *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        /* Try wide path */
        WCHAR wpath[MAX_PATH];
        MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, MAX_PATH);
        f = _wfopen(wpath, L"rb");
        if (!f) return NULL;
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0 || sz > 4 * 1024 * 1024) { fclose(f); return NULL; }
    unsigned char *buf = (unsigned char *)malloc(sz);
    if (!buf) { fclose(f); return NULL; }
    fread(buf, 1, sz, f);
    fclose(f);
    *out_len = (int)sz;
    return buf;
}

HBITMAP image_load(const char *source, int req_w, int req_h, int *out_w, int *out_h) {
    if (!source || !source[0]) return NULL;

    char key[512];
    make_cache_key(source, req_w, req_h, key, sizeof(key));

    EnterCriticalSection(&g_img_cs);
    CachedImage *cached = cache_find(key);
    if (cached) {
        *out_w = cached->width;
        *out_h = cached->height;
        HBITMAP result = cache_get_current_frame(cached);
        LeaveCriticalSection(&g_img_cs);
        return result;
    }
    LeaveCriticalSection(&g_img_cs);

    /* Load raw data based on source type */
    unsigned char *raw_data = NULL;
    int raw_len = 0;

    if (strncmp(source, "data:", 5) == 0) {
        const char *comma = strchr(source, ',');
        if (comma) {
            raw_data = (unsigned char *)base64_decode(comma + 1, &raw_len);
        }
    } else if (strncmp(source, "http://", 7) == 0 || strncmp(source, "https://", 8) == 0) {
        WCHAR wurl[2048];
        MultiByteToWideChar(CP_UTF8, 0, source, -1, wurl, 2048);
        raw_data = (unsigned char *)http_request_sync(wurl, L"GET", NULL, NULL, &raw_len, 4 * 1024 * 1024);
    } else {
        raw_data = load_file_mem(source, &raw_len);
    }

    if (!raw_data || raw_len <= 0) {
        if (raw_data) free(raw_data);
        return NULL;
    }

    /* Check if animated GIF */
    if (is_gif_data(raw_data, raw_len)) {
        EnterCriticalSection(&g_img_cs);
        CachedImage *slot;
        if (g_img_count >= IMG_CACHE_MAX) {
            if (g_img_cache[0].frame_count > 1) {
                for (int f = 0; f < g_img_cache[0].frame_count; f++)
                    if (g_img_cache[0].frames[f]) DeleteObject(g_img_cache[0].frames[f]);
            } else {
                if (g_img_cache[0].hbmp) DeleteObject(g_img_cache[0].hbmp);
            }
            memmove(&g_img_cache[0], &g_img_cache[1], sizeof(CachedImage) * (IMG_CACHE_MAX - 1));
            g_img_count = IMG_CACHE_MAX - 1;
        }
        slot = &g_img_cache[g_img_count];
        memset(slot, 0, sizeof(CachedImage));
        strncpy(slot->key, key, sizeof(slot->key) - 1);

        if (decode_gif_animated(raw_data, raw_len, req_w, req_h, slot)) {
            g_img_count++;
            *out_w = slot->width;
            *out_h = slot->height;
            HBITMAP result = cache_get_current_frame(slot);
            LeaveCriticalSection(&g_img_cs);
            free(raw_data);
            return result;
        }
        LeaveCriticalSection(&g_img_cs);
        /* Fall through to static decode if GIF parse failed */
    }

    /* Static image decode */
    int w = 0, h = 0;
    HBITMAP hbmp = decode_image_mem(raw_data, raw_len, req_w, req_h, &w, &h);
    free(raw_data);

    if (hbmp) {
        EnterCriticalSection(&g_img_cs);
        cache_add(key, hbmp, w, h);
        LeaveCriticalSection(&g_img_cs);
        *out_w = w;
        *out_h = h;
    }
    return hbmp;
}

BOOL image_is_animated(const char *source, int req_w, int req_h) {
    if (!source || !source[0]) return FALSE;
    char key[512];
    make_cache_key(source, req_w, req_h, key, sizeof(key));
    EnterCriticalSection(&g_img_cs);
    CachedImage *cached = cache_find(key);
    BOOL result = (cached && cached->frame_count > 1);
    LeaveCriticalSection(&g_img_cs);
    return result;
}