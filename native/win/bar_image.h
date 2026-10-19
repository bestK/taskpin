// ============================================================================
//  TaskPin bar — image decode for the Direct2D surface
// ============================================================================
//  PNG / JPEG / BMP / GIF via stb_image (read-only include of lib/stb_image.h),
//  plus data: URIs and http(s) URLs. Produces ID2D1Bitmap objects owned by the
//  module cache (do NOT release the returned bitmap).
//
//  Mirrors lib/image.c's source handling and animated-GIF timing so the bar
//  behaves the same; the difference is the output type (ID2D1Bitmap instead of
//  HBITMAP) because the renderer is Direct2D.
// ============================================================================
#ifndef TASKPIN_BAR_IMAGE_H
#define TASKPIN_BAR_IMAGE_H

#include <windows.h>
#include <d2d1_1.h>
#include <string>

namespace taskpin {
namespace bar {

void BarImageInit();
void BarImageShutdown();

// Load (or fetch from cache) an image. `source` is UTF-8 and may be a file
// path, an http(s) URL, or a data: URI. req_w/req_h of 0 mean natural size.
// Returns a cached ID2D1Bitmap (do not Release) or nullptr on failure.
// out_w/out_h receive the display size.
ID2D1Bitmap* BarImageGet(ID2D1DeviceContext* ctx, const char* source,
                         int req_w, int req_h, int* out_w, int* out_h);

// Wide-source convenience overload (span text is wide in the native model).
ID2D1Bitmap* BarImageGet(ID2D1DeviceContext* ctx, const wchar_t* source,
                         int req_w, int req_h, int* out_w, int* out_h);

// True when the source decoded to a multi-frame (animated) image.
bool BarImageIsAnimated(const char* source, int req_w, int req_h);
bool BarImageIsAnimated(const wchar_t* source, int req_w, int req_h);

// Drop every device-dependent bitmap. Must be called when the D2D device is
// recreated (device loss / DPI change) so stale bitmaps are not reused.
void BarImageOnDeviceLost();

} // namespace bar
} // namespace taskpin

#endif // TASKPIN_BAR_IMAGE_H
