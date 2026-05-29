#ifndef TASKPIN_IMAGE_H
#define TASKPIN_IMAGE_H

#include <windows.h>

/* Image cache entry */
#define IMG_CACHE_MAX 32
#define IMG_MAX_FRAMES 64

typedef struct {
    char key[512];       /* source identifier (path/url/base64 prefix) */
    HBITMAP hbmp;        /* single-frame bitmap (or first frame) */
    int width, height;
    /* Animated GIF support */
    HBITMAP frames[IMG_MAX_FRAMES];
    int delays[IMG_MAX_FRAMES]; /* per-frame delay in ms */
    int frame_count;            /* 0 or 1 = static image */
    DWORD start_tick;           /* GetTickCount() when first loaded */
} CachedImage;

/* Initialize image subsystem */
void image_init(void);

/* Shutdown and free all cached bitmaps */
void image_shutdown(void);

/* Load image from source string. Returns cached HBITMAP (do NOT delete).
   source can be:
     - local file path (absolute or relative to exe)
     - URL (http:// or https://)
     - data URI: "data:image/png;base64,..."
   For animated GIFs, returns the current frame based on elapsed time.
   out_w/out_h receive image dimensions.
   Returns NULL on failure. */
HBITMAP image_load(const char *source, int req_w, int req_h, int *out_w, int *out_h);

/* Check if a previously loaded image source is an animated GIF (multi-frame). */
BOOL image_is_animated(const char *source, int req_w, int req_h);

#endif