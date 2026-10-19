// ============================================================================
//  TaskPin bar — Direct2D + DirectWrite renderer
// ============================================================================
//  Replaces the GDI path in src/bar_window.c (TextOutW / GetTextExtentPoint32).
//  DirectWrite gives us what GDI cannot:
//    - correct CJK font fallback
//    - COLOUR EMOJI  (D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT)
//    - per-glyph alpha and real subpixel control
//    - tabular numerals for metrics (no jitter when CPU: 9% -> CPU: 100%)
//
//  Surface: D3D11 -> DXGI swapchain -> ID2D1DeviceContext (D2D 1.1), NOT
//  ID2D1HwndRenderTarget, because colour-font rendering requires D2D 1.1.
//  A layered (transparent) variant renders into a WIC bitmap instead and the
//  caller blits it with UpdateLayeredWindow.
// ============================================================================
#ifndef TASKPIN_BAR_RENDER_D2D_H
#define TASKPIN_BAR_RENDER_D2D_H

#include <windows.h>
#include <d2d1_1.h>
#include <dwrite.h>
#include <dwrite_2.h>
#include <wincodec.h>
#include <dxgi1_2.h>
#include <d3d11.h>
#include <cstdint>
#include <string>
#include <vector>
#include "bar_types.h"

namespace taskpin {
namespace bar {

// -------------------------------------------------------- device factory ----
// Process-wide D2D/DWrite/D3D/WIC singletons, shared by every bar.
struct D2DGlobals {
    ID2D1Factory1*     d2d   = nullptr;
    IDWriteFactory*    dwrite = nullptr;
    IDWriteFactory2*   dwrite2 = nullptr;  // GetSystemFontFallback (CJK)
    IWICImagingFactory* wic   = nullptr;
    ID3D11Device*      d3d    = nullptr;
    IDXGIDevice*       dxgi   = nullptr;
    ID2D1Device*       d2d_device = nullptr;
    IDXGIFactory2*     dxgi_factory = nullptr;
    bool               hardware = false;

    bool valid() const {
        return d2d && dwrite && d2d_device && wic && dxgi_factory;
    }
};

// Create (once) / release the process-wide globals. Returns false on failure.
bool D2DGlobalsInit(D2DGlobals* g);
void D2DGlobalsRelease(D2DGlobals* g);

// -------------------------------------------------------------- renderer ----
class BarRenderer {
public:
    BarRenderer();
    ~BarRenderer();

    // Bind to a window. `layered` selects the transparent (WIC bitmap +
    // UpdateLayeredWindow) path. Idempotent; re-binds on size change.
    bool Attach(D2DGlobals* globals, HWND hwnd, bool layered);
    void Detach();

    // Recreate device resources after D2DERR_RECREATE_TARGET / DPI change.
    bool ResetDevice();
    // Recreate size-dependent resources (swapchain buffers / WIC bitmap).
    bool Resize(int w, int h, UINT dpi);

    bool layered() const { return m_layered; }
    UINT dpi() const { return m_dpi; }
    bool attached() const { return m_ctx != nullptr; }

    // Draw one frame. `hover` selects bar/bgHover + hairlines.
    // Returns true on success, false when the device was lost (caller should
    // ResetDevice() + Resize() and try again).
    bool Render(const SpanContent& content, const BarStyle& style,
                int width, int height, bool hover, int scroll_offset);

    // ---- test seam (offscreen, no window) --------------------------------
    // Render into an offscreen WIC bitmap of the given size and read it back as
    // premultiplied BGRA. Used by the --selftest colour-font assertion.
    bool RenderOffscreen(D2DGlobals* globals, const SpanContent& content,
                         const BarStyle& style, int width, int height,
                         std::vector<uint8_t>* out_bgra);

    // Per-span layout diagnostics (logged by the demo so text metrics are
    // observable, not just visual).
    struct SpanLayoutInfo {
        int  index = 0;
        int  x = 0, y = 0, w = 0, h = 0;
        int  line = 0;
        bool is_image = false;
        float dw_width = 0, dw_height = 0;  // DirectWrite metrics
    };
    const std::vector<SpanLayoutInfo>& last_layout() const { return m_last_layout; }

    // Sum of left/centre-aligned span widths on a line. Mirrors the source's
    // `left_total[0]` (src/bar_window.c:211), which the marquee compares
    // against the available width — right-aligned spans must NOT count, or a
    // right-aligned value makes the bar scroll when it should not.
    int last_left_total(int line) const {
        return (line >= 0 && line < 2) ? m_last_left_total[line] : 0;
    }

private:
    bool CreateDeviceResources();
    void DiscardDeviceResources();
    bool CreateTargetBitmap();
    // Copy the WIC render target into a top-down 32-bit DIB (caller owns it).
    HBITMAP ReadbackToDib(void** out_bits);
    void DrawFrame(const SpanContent& content, const BarStyle& style,
                   int width, int height, bool hover, int scroll_offset);
    IDWriteTextFormat* GetFormat(const Span& span, const BarStyle& style);
    IDWriteTextLayout* MakeLayout(const Span& span, const BarStyle& style,
                                  float max_w, float max_h);

    D2DGlobals* m_globals = nullptr;
    HWND m_hwnd = nullptr;
    bool m_layered = false;
    UINT m_dpi = 96;
    int  m_w = 0, m_h = 0;

    // Opaque path
    IDXGISwapChain1*   m_swapchain = nullptr;
    // Layered path
    IWICBitmap*        m_wic_bitmap = nullptr;
    // Shared
    ID2D1DeviceContext* m_ctx = nullptr;
    ID2D1Bitmap1*      m_target = nullptr;
    ID2D1SolidColorBrush* m_brush = nullptr;

    // Cached text formats keyed by "size|weight".
    struct FormatKey { int size_pt; bool tabular; };
    std::vector<std::pair<uint64_t, IDWriteTextFormat*>> m_formats;

    std::vector<SpanLayoutInfo> m_last_layout;
    int m_last_left_total[2] = {0, 0};
    bool m_offscreen = false;   // true while rendering into a test bitmap
};

} // namespace bar
} // namespace taskpin

#endif // TASKPIN_BAR_RENDER_D2D_H
