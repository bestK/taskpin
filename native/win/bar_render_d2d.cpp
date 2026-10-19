// ============================================================================
//  TaskPin bar — Direct2D + DirectWrite renderer (implementation)
// ============================================================================
#include "bar_render_d2d.h"
#include "bar_image.h"
#include "bar_embed.h"

#include <d2d1_1helper.h>
#include <d2d1helper.h>
#include <cmath>
#include <cstring>

namespace taskpin {
namespace bar {

namespace {

// Points -> DIP (1 DIP = 1/96 inch, 1pt = 1/72 inch).
inline float PtToDip(int pt) { return pt * 96.0f / 72.0f; }

// D2D1::ColorF from 0xAARRGGBB.
inline D2D1_COLOR_F ToColorF(uint32_t c) {
    return D2D1::ColorF(ColorR(c), ColorG(c), ColorB(c), ColorA(c));
}

// The shell font. The plan says the bar uses the system font to match the
// shell (Segoe UI Variable on Win11, Segoe UI on Win10) — NOT Inter.
const wchar_t* ShellFontFamily() { return L"Segoe UI"; }

// DirectWrite automatic fallback handles CJK + emoji; we additionally wire the
// system fallback onto the format so a missing family cannot produce tofu.
IDWriteFontFallback* SystemFallback(D2DGlobals* g) {
    static IDWriteFontFallback* cached = nullptr;
    if (cached) return cached;
    if (!g || !g->dwrite2) return nullptr;
    IDWriteFontFallback* fb = nullptr;
    if (SUCCEEDED(g->dwrite2->GetSystemFontFallback(&fb))) cached = fb;
    return cached;
}

} // namespace

// ------------------------------------------------------- globals -----------

bool D2DGlobalsInit(D2DGlobals* g) {
    if (!g) return false;
    if (g->valid()) return true;

    // Direct2D 1.1 factory (explicit IID: the template overload is ambiguous
    // under MinGW).
    D2D1_FACTORY_OPTIONS opts = { D2D1_DEBUG_LEVEL_NONE };
    HRESULT hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                                   __uuidof(ID2D1Factory1), &opts,
                                   reinterpret_cast<void**>(&g->d2d));
    if (FAILED(hr)) { bar_log("D2D: D2D1CreateFactory failed hr=0x%08lX", (unsigned long)hr); return false; }

    // DirectWrite + DirectWrite 1.1/2 for the system font fallback (CJK).
    hr = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                             reinterpret_cast<IUnknown**>(&g->dwrite));
    if (FAILED(hr)) { bar_log("D2D: DWriteCreateFactory failed hr=0x%08lX", (unsigned long)hr); return false; }
    if (FAILED(g->dwrite->QueryInterface(__uuidof(IDWriteFactory2),
                                         reinterpret_cast<void**>(&g->dwrite2)))) {
        bar_log("D2D: IDWriteFactory2 unavailable (CJK fallback will rely on DW default)");
        g->dwrite2 = nullptr;
    }

    // WIC (bitmap targets for the layered + offscreen paths).
    hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                          __uuidof(IWICImagingFactory), reinterpret_cast<void**>(&g->wic));
    if (FAILED(hr)) { bar_log("D2D: WIC factory failed hr=0x%08lX", (unsigned long)hr); return false; }

    // D3D11 device (hardware, WARP fallback).
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0,
                                   D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0 };
    D3D_FEATURE_LEVEL got = D3D_FEATURE_LEVEL_10_0;
    hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
                           levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                           &g->d3d, &got, nullptr);
    if (FAILED(hr)) {
        bar_log("D2D: hardware D3D11 failed hr=0x%08lX, trying WARP", (unsigned long)hr);
        hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags,
                               levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                               &g->d3d, &got, nullptr);
    }
    if (FAILED(hr)) { bar_log("D2D: D3D11CreateDevice failed hr=0x%08lX", (unsigned long)hr); return false; }
    g->hardware = (got >= D3D_FEATURE_LEVEL_11_0);
    bar_log("D2D: D3D11 device ok feature_level=0x%04X (%s)", (unsigned)got,
            g->hardware ? "hardware" : "warp/basic");

    if (FAILED(g->d3d->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void**>(&g->dxgi)))) {
        bar_log("D2D: IDXGIDevice QI failed"); return false;
    }
    if (FAILED(g->d2d->CreateDevice(g->dxgi, &g->d2d_device))) {
        bar_log("D2D: CreateDevice failed"); return false;
    }

    // DXGI factory (swapchain creation for the opaque path).
    IDXGIAdapter* adapter = nullptr;
    if (SUCCEEDED(g->dxgi->GetAdapter(&adapter)) && adapter) {
        adapter->GetParent(__uuidof(IDXGIFactory2), reinterpret_cast<void**>(&g->dxgi_factory));
        adapter->Release();
    }

    bar_log("D2D: globals ready (d2d=%p dwrite=%p dwrite2=%p wic=%p d2d_device=%p dxgi_factory=%p)",
            (void*)g->d2d, (void*)g->dwrite, (void*)g->dwrite2, (void*)g->wic,
            (void*)g->d2d_device, (void*)g->dxgi_factory);
    return g->valid();
}

void D2DGlobalsRelease(D2DGlobals* g) {
    if (!g) return;
    if (g->dxgi_factory) { g->dxgi_factory->Release(); g->dxgi_factory = nullptr; }
    if (g->d2d_device)   { g->d2d_device->Release();   g->d2d_device = nullptr; }
    if (g->dxgi)         { g->dxgi->Release();         g->dxgi = nullptr; }
    if (g->d3d)          { g->d3d->Release();          g->d3d = nullptr; }
    if (g->wic)          { g->wic->Release();          g->wic = nullptr; }
    if (g->dwrite2)      { g->dwrite2->Release();      g->dwrite2 = nullptr; }
    if (g->dwrite)       { g->dwrite->Release();       g->dwrite = nullptr; }
    if (g->d2d)          { g->d2d->Release();          g->d2d = nullptr; }
}

// ------------------------------------------------------- renderer ----------

BarRenderer::BarRenderer() {}
BarRenderer::~BarRenderer() { Detach(); D2DGlobalsRelease(nullptr); }

bool BarRenderer::Attach(D2DGlobals* globals, HWND hwnd, bool layered) {
    if (!globals || !globals->valid() || !hwnd) return false;
    m_globals = globals;
    m_hwnd = hwnd;
    m_layered = layered;
    m_dpi = bar_embed_dpi_for_window(hwnd);

    RECT rc;
    GetClientRect(hwnd, &rc);
    m_w = rc.right - rc.left;
    m_h = rc.bottom - rc.top;
    if (m_w <= 0) m_w = 100;
    if (m_h <= 0) m_h = kHeightWin10;

    return CreateDeviceResources();
}

void BarRenderer::Detach() {
    DiscardDeviceResources();
    for (auto& kv : m_formats) if (kv.second) kv.second->Release();
    m_formats.clear();
    m_globals = nullptr;
    m_hwnd = nullptr;
}

void BarRenderer::DiscardDeviceResources() {
    if (m_target)    { m_target->Release();    m_target = nullptr; }
    if (m_brush)     { m_brush->Release();     m_brush = nullptr; }
    if (m_ctx)       { m_ctx->Release();       m_ctx = nullptr; }
    if (m_swapchain) { m_swapchain->Release(); m_swapchain = nullptr; }
    if (m_wic_bitmap){ m_wic_bitmap->Release();m_wic_bitmap = nullptr; }
}

bool BarRenderer::CreateDeviceResources() {
    DiscardDeviceResources();
    if (!m_globals || !m_globals->d2d_device) return false;

    HRESULT hr = m_globals->d2d_device->CreateDeviceContext(
        D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &m_ctx);
    if (FAILED(hr)) { bar_log("render: CreateDeviceContext hr=0x%08lX", (unsigned long)hr); return false; }

    // Render in DIPs; the context DPI maps DIP -> physical pixels.
    m_ctx->SetDpi(static_cast<float>(m_dpi), static_cast<float>(m_dpi));
    m_ctx->SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    m_ctx->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);

    if (!CreateTargetBitmap()) return false;

    hr = m_ctx->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::White), &m_brush);
    if (FAILED(hr)) { bar_log("render: CreateSolidColorBrush hr=0x%08lX", (unsigned long)hr); return false; }
    return true;
}

bool BarRenderer::CreateTargetBitmap() {
    if (!m_ctx) return false;
    if (m_target) { m_target->Release(); m_target = nullptr; }

    D2D1_BITMAP_PROPERTIES1 props = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_TARGET,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED),
        static_cast<float>(m_dpi), static_cast<float>(m_dpi));

    // We render into a plain D2D bitmap and present by blitting, because a DXGI
    // swapchain cannot be created on a child window inside another process's
    // window tree (explorer's taskbar): CreateSwapChainForHwnd returns
    // E_ACCESSDENIED there. Rendering is still 100% Direct2D + DirectWrite;
    // only the presentation differs:
    //   opaque  -> BitBlt
    //   layered -> UpdateLayeredWindow
    // Note: a WIC-backed target (CreateBitmapFromWicBitmap) does not reliably
    // reflect the rendered pixels back into the WIC bitmap, so we use a real
    // D2D bitmap target and read it back through a CPU_READ bitmap instead.
    HRESULT hr = m_ctx->CreateBitmap(
        D2D1::SizeU(static_cast<UINT32>(m_w), static_cast<UINT32>(m_h)),
        nullptr, 0, props, &m_target);
    if (FAILED(hr) || !m_target) {
        bar_log("render: CreateBitmap(target) hr=0x%08lX", (unsigned long)hr);
        return false;
    }

    m_ctx->SetTarget(m_target);
    return true;
}

// Copy the D2D render target into a top-down 32-bit DIB. Caller owns the DIB.
HBITMAP BarRenderer::ReadbackToDib(void** out_bits) {
    if (!m_ctx || !m_target || !out_bits) return nullptr;

    const D2D1_SIZE_U size = D2D1::SizeU(static_cast<UINT32>(m_w), static_cast<UINT32>(m_h));
    const D2D1_PIXEL_FORMAT pf =
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED);
    D2D1_BITMAP_PROPERTIES1 cprops = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_CPU_READ | D2D1_BITMAP_OPTIONS_CANNOT_DRAW, pf,
        static_cast<float>(m_dpi), static_cast<float>(m_dpi));

    ID2D1Bitmap1* cpu = nullptr;
    if (FAILED(m_ctx->CreateBitmap(size, nullptr, 0, cprops, &cpu)) || !cpu) return nullptr;
    HRESULT chr = cpu->CopyFromBitmap(nullptr, m_target, nullptr);
    if (FAILED(chr)) { cpu->Release(); return nullptr; }

    D2D1_MAPPED_RECT mapped = {};
    if (FAILED(cpu->Map(D2D1_MAP_OPTIONS_READ, &mapped))) { cpu->Release(); return nullptr; }

    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = m_w;
    bmi.bmiHeader.biHeight = -m_h;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HDC screen = GetDC(nullptr);
    HBITMAP dib = CreateDIBSection(screen, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (dib && bits) {
        const size_t row = static_cast<size_t>(m_w) * 4;
        for (int y = 0; y < m_h; ++y)
            memcpy(static_cast<BYTE*>(bits) + static_cast<size_t>(y) * row,
                   mapped.bits + static_cast<size_t>(y) * mapped.pitch, row);
        *out_bits = bits;
    }
    if (screen) ReleaseDC(nullptr, screen);
    cpu->Unmap();
    cpu->Release();
    return dib;
}

bool BarRenderer::ResetDevice() {
    // Device-dependent image bitmaps are invalid after a device loss.
    BarImageOnDeviceLost();
    return CreateDeviceResources();
}

bool BarRenderer::Resize(int w, int h, UINT dpi) {
    if (w <= 0 || h <= 0) return false;
    m_w = w; m_h = h;
    if (dpi) m_dpi = dpi;
    if (m_ctx) m_ctx->SetDpi(static_cast<float>(m_dpi), static_cast<float>(m_dpi));
    return CreateTargetBitmap();
}

// ------------------------------------------------------- text -------------

IDWriteTextFormat* BarRenderer::GetFormat(const Span& span, const BarStyle& style) {
    if (!m_globals || !m_globals->dwrite) return nullptr;
    int pt = span.font_size > 0 ? span.font_size : style.font_size;
    if (pt < 6) pt = 6;
    if (pt > 72) pt = 72;
    uint64_t key = static_cast<uint64_t>(pt) | (span.tabular ? (1ull << 32) : 0);
    for (auto& kv : m_formats) if (kv.first == key) return kv.second;

    IDWriteTextFormat* fmt = nullptr;
    HRESULT hr = m_globals->dwrite->CreateTextFormat(
        ShellFontFamily(), nullptr, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
        DWRITE_FONT_STRETCH_NORMAL, PtToDip(pt), L"en-us", &fmt);
    if (FAILED(hr)) return nullptr;

    // Wire the system fallback so CJK/emoji never render as tofu even if the
    // family name has no coverage.
    IDWriteTextFormat1* fmt1 = nullptr;
    if (SUCCEEDED(fmt->QueryInterface(__uuidof(IDWriteTextFormat1),
                                      reinterpret_cast<void**>(&fmt1))) && fmt1) {
        IDWriteFontFallback* fb = SystemFallback(m_globals);
        if (fb) fmt1->SetFontFallback(fb);
        fmt1->Release();
    }
    m_formats.emplace_back(key, fmt);
    return fmt;
}

IDWriteTextLayout* BarRenderer::MakeLayout(const Span& span, const BarStyle& style,
                                           float max_w, float max_h) {
    IDWriteTextFormat* fmt = GetFormat(span, style);
    if (!fmt) return nullptr;

    IDWriteTextLayout* layout = nullptr;
    HRESULT hr = m_globals->dwrite->CreateTextLayout(
        span.text.c_str(), static_cast<UINT32>(span.text.size()), fmt,
        max_w > 0 ? max_w : 4096.0f, max_h > 0 ? max_h : 256.0f, &layout);
    if (FAILED(hr) || !layout) return nullptr;

    layout->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);

    // Tabular numerals for metrics: keeps "CPU: 9%" -> "CPU: 100%" from shifting
    // everything to its right.
    if (span.tabular && m_globals->dwrite) {
        IDWriteTypography* typo = nullptr;
        if (SUCCEEDED(m_globals->dwrite->CreateTypography(&typo)) && typo) {
            DWRITE_FONT_FEATURE feat = { DWRITE_FONT_FEATURE_TAG_TABULAR_FIGURES, 1 };
            typo->AddFontFeature(feat);
            layout->SetTypography(typo, { 0, static_cast<UINT32>(span.text.size()) });
            typo->Release();
        }
    }
    return layout;
}

// ------------------------------------------------------- draw -------------

void BarRenderer::DrawFrame(const SpanContent& content, const BarStyle& style,
                            int width, int height, bool hover, int scroll_offset) {
    if (!m_ctx) return;
    m_last_layout.clear();
    m_last_left_total[0] = m_last_left_total[1] = 0;

    const float scale = static_cast<float>(m_dpi) / 96.0f;
    const float w = static_cast<float>(width)  / scale;
    const float h = static_cast<float>(height) / scale;

    // ---- background ----
    m_ctx->Clear(hover ? ToColorF(style.bgHover) : ToColorF(style.bg));
    if (!hover && style.bg != 0 && ColorA(style.bg) < 1.0f) {
        // Clear() with a transparent colour on an opaque target can leave the
        // previous frame; an explicit fill makes it deterministic.
        m_brush->SetColor(ToColorF(style.bg));
        m_ctx->FillRectangle(D2D1::RectF(0, 0, w, h), m_brush);
    }

    // ---- 2px full-height left state stripe ----
    uint32_t stripe = kColorStateRunning;
    if (style.state == StateError) stripe = kColorStateError;
    else if (style.state == StateStale) stripe = kColorStateStale;
    if (ColorA(stripe) > 0.0f) {
        m_brush->SetColor(ToColorF(stripe));
        m_ctx->FillRectangle(D2D1::RectF(0, 0, static_cast<float>(kMetricStateStripe), h), m_brush);
    }

    // ---- hover hairlines (1px inset top/bottom) ----
    if (hover) {
        m_brush->SetColor(ToColorF(kColorHairline));
        const float t = static_cast<float>(kMetricHairline);
        m_ctx->FillRectangle(D2D1::RectF(0, 0, w, t), m_brush);
        m_ctx->FillRectangle(D2D1::RectF(0, h - t, w, h), m_brush);
    }

    if (content.spans.empty()) return;

    const float margin = static_cast<float>(kMetricPadH);
    const bool has_newline = content.HasNewline();
    float line_y[2];
    if (has_newline) { line_y[0] = 2.0f; line_y[1] = h / 2.0f + 1.0f; }
    else             { line_y[0] = 0.0f; line_y[1] = 0.0f; }

    // ---- measure pass ----
    struct Item {
        const Span* span = nullptr;
        int   line = 0;
        float w = 0, h = 0;
        IDWriteTextLayout* layout = nullptr;
        ID2D1Bitmap* bmp = nullptr;
        float bmp_w = 0, bmp_h = 0;
    };
    std::vector<Item> items;
    items.reserve(content.spans.size());

    int cur_line = 0;
    for (const Span& sp : content.spans) {
        if (sp.newline) { cur_line = 1; continue; }
        Item it;
        it.span = &sp;
        it.line = cur_line;

        if (sp.is_image) {
            int iw = 0, ih = 0;
            it.bmp = BarImageGet(m_ctx, sp.text.c_str(), sp.img_w, sp.img_h, &iw, &ih);
            it.bmp_w = static_cast<float>(iw) / scale;
            it.bmp_h = static_cast<float>(ih) / scale;
            it.w = it.bmp ? it.bmp_w : 0;
            it.h = it.bmp ? it.bmp_h : 0;
        } else if (!sp.text.empty()) {
            it.layout = MakeLayout(sp, style, w, h);
            if (it.layout) {
                DWRITE_TEXT_METRICS tm = {};
                if (SUCCEEDED(it.layout->GetMetrics(&tm))) {
                    it.w = tm.widthIncludingTrailingWhitespace > 0 ? tm.widthIncludingTrailingWhitespace : tm.width;
                    it.h = tm.height;
                }
            }
        }
        // Mirror the source's left_total[] (src/bar_window.c:126,142,211): only
        // non-right-aligned spans contribute to the marquee width. Stored in
        // physical pixels to compare against the bar width.
        if (sp.align != AlignRight && it.w > 0)
            m_last_left_total[cur_line] += static_cast<int>(it.w * scale);
        items.push_back(it);
    }

    // ---- position pass (mirrors src/bar_window.c:147-210) ----
    float left_x[2]  = { margin - static_cast<float>(scroll_offset), margin };
    float right_x[2] = { w - margin, w - margin };
    const float sep_advance = style.show_separators
        ? static_cast<float>(kMetricSepGap * 2 + kMetricSepWidth) : 0.0f;

    for (size_t i = 0; i < items.size(); ++i) {
        Item& it = items[i];
        if (it.w <= 0 && !it.layout && !it.bmp) continue;
        const int ln = it.line;
        float x;
        if (it.span->align == AlignRight) {
            right_x[ln] -= it.w;
            x = right_x[ln];
        } else if (it.span->align == AlignCenter) {
            x = (w - it.w) / 2.0f;
        } else {
            x = left_x[ln];
            left_x[ln] += it.w;
        }
        float y = has_newline ? line_y[ln] : (h - it.h) / 2.0f;

        // Separator before this span (except the first on its line).
        if (style.show_separators && it.span->align != AlignRight) {
            bool first_on_line = true;
            for (size_t j = 0; j < i; ++j)
                if (items[j].line == ln && items[j].w > 0) { first_on_line = false; break; }
            if (!first_on_line) {
                float sx = x - static_cast<float>(kMetricSepGap + kMetricSepWidth);
                float sy = (h - static_cast<float>(kMetricSepHeight)) / 2.0f;
                m_brush->SetColor(ToColorF(kColorSeparator));
                m_ctx->FillRectangle(
                    D2D1::RectF(sx, sy, sx + static_cast<float>(kMetricSepWidth),
                                sy + static_cast<float>(kMetricSepHeight)), m_brush);
            }
        }

        // Draw.
        if (it.bmp) {
            D2D1_RECT_F dst = D2D1::RectF(x, y, x + it.bmp_w, y + it.bmp_h);
            m_ctx->DrawBitmap(it.bmp, &dst, 1.0f, D2D1_INTERPOLATION_MODE_LINEAR, nullptr);
        } else if (it.layout) {
            uint32_t col = (it.span->color != 0xFFFFFFFFu) ? it.span->color : style.value;
            m_brush->SetColor(ToColorF(col));
            // ENABLE_COLOR_FONT is what makes Segoe UI Emoji render in colour —
            // GDI cannot do this. This is the proof the D2D path is live.
            m_ctx->DrawTextLayout(D2D1::Point2F(x, y), it.layout, m_brush,
                                  D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT);
        }

        SpanLayoutInfo info;
        info.index = static_cast<int>(i);
        info.x = static_cast<int>(x * scale);
        info.y = static_cast<int>(y * scale);
        info.w = static_cast<int>(it.w * scale);
        info.h = static_cast<int>(it.h * scale);
        info.line = ln;
        info.is_image = it.bmp != nullptr;
        info.dw_width = it.w;
        info.dw_height = it.h;
        m_last_layout.push_back(info);

        if (it.layout) it.layout->Release();
        if (it.span->align != AlignRight && it.span->align != AlignCenter && it.w > 0)
            left_x[ln] += sep_advance;
    }
}

bool BarRenderer::Render(const SpanContent& content, const BarStyle& style,
                         int width, int height, bool hover, int scroll_offset) {
    if (!m_ctx) return false;
    if (width != m_w || height != m_h) {
        m_w = width; m_h = height;
        if (!CreateTargetBitmap()) return false;
    }

    m_ctx->BeginDraw();
    DrawFrame(content, style, width, height, hover, scroll_offset);
    HRESULT hr = m_ctx->EndDraw();
    if (hr == static_cast<HRESULT>(D2DERR_RECREATE_TARGET)) {
        bar_log("render: D2DERR_RECREATE_TARGET -> rebuilding device resources");
        if (!CreateDeviceResources()) return false;
        m_ctx->BeginDraw();
        DrawFrame(content, style, width, height, hover, scroll_offset);
        hr = m_ctx->EndDraw();
        if (FAILED(hr)) return false;
    } else if (FAILED(hr)) {
        return false;
    }

    if (m_layered) {
        // Transparent path: UpdateLayeredWindow with per-pixel alpha. A child
        // window cannot truly pass clicks through; this is alpha only.
        void* bits = nullptr;
        HBITMAP dib = ReadbackToDib(&bits);
        if (!dib) return false;
        HDC screen = GetDC(nullptr);
        HDC memdc = CreateCompatibleDC(screen);
        HGDIOBJ old = SelectObject(memdc, dib);
        POINT dst = { 0, 0 }, src = { 0, 0 };
        SIZE size = { m_w, m_h };
        BLENDFUNCTION bf = { AC_SRC_OVER, 0, 255, AC_SRC_ALPHA };
        UpdateLayeredWindow(m_hwnd, screen, &dst, &size, memdc, &src, 0, &bf, ULW_ALPHA);
        SelectObject(memdc, old);
        DeleteDC(memdc);
        ReleaseDC(nullptr, screen);
        DeleteObject(dib);
        return true;
    }

    // Opaque path: BitBlt the frame onto the child window's DC.
    void* bits = nullptr;
    HBITMAP dib = ReadbackToDib(&bits);
    if (!dib) return false;
    HDC wnd = GetDC(m_hwnd);
    HDC memdc = CreateCompatibleDC(wnd);
    HGDIOBJ old = SelectObject(memdc, dib);
    BitBlt(wnd, 0, 0, m_w, m_h, memdc, 0, 0, SRCCOPY);
    SelectObject(memdc, old);
    DeleteDC(memdc);
    ReleaseDC(m_hwnd, wnd);
    DeleteObject(dib);
    return true;
}

// ------------------------------------------------------- offscreen ---------

bool BarRenderer::RenderOffscreen(D2DGlobals* globals, const SpanContent& content,
                                  const BarStyle& style, int width, int height,
                                  std::vector<uint8_t>* out_bgra) {
    if (!globals || !globals->valid() || width <= 0 || height <= 0 || !out_bgra) return false;

    // Canonical device-context readback: render into a TARGET bitmap, then copy
    // into a CPU_READ bitmap and Map() it. (Rendering straight into an
    // IWICBitmap target from a D3D-backed device context does not reliably
    // reflect the pixels back into the WIC bitmap.)
    ID2D1DeviceContext* ctx = nullptr;
    if (FAILED(globals->d2d_device->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &ctx)))
        return false;
    ctx->SetDpi(96.0f, 96.0f);
    ctx->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);

    const D2D1_SIZE_U size = D2D1::SizeU(static_cast<UINT32>(width), static_cast<UINT32>(height));
    const D2D1_PIXEL_FORMAT pf =
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED);

    D2D1_BITMAP_PROPERTIES1 tprops = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_TARGET, pf, 96.0f, 96.0f);
    ID2D1Bitmap1* target = nullptr;
    if (FAILED(ctx->CreateBitmap(size, nullptr, 0, tprops, &target)) || !target) {
        ctx->Release();
        return false;
    }
    ctx->SetTarget(target);

    ID2D1SolidColorBrush* brush = nullptr;
    ctx->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::White), &brush);

    // Save + install offscreen state so the exact same DrawFrame() runs.
    D2DGlobals* sg = m_globals; HWND sh = m_hwnd; bool sl = m_layered;
    UINT sd = m_dpi; int sw = m_w, shh = m_h; bool so = m_offscreen;
    ID2D1DeviceContext* sc = m_ctx; ID2D1Bitmap1* st = m_target;
    ID2D1SolidColorBrush* sb = m_brush;
    m_globals = globals; m_hwnd = nullptr; m_layered = false;
    m_dpi = 96; m_w = width; m_h = height; m_offscreen = true;
    m_ctx = ctx; m_target = target; m_brush = brush;

    ctx->BeginDraw();
    DrawFrame(content, style, width, height, false, 0);
    HRESULT hr = ctx->EndDraw();

    // Restore.
    m_globals = sg; m_hwnd = sh; m_layered = sl; m_dpi = sd;
    m_w = sw; m_h = shh; m_offscreen = so;
    m_ctx = sc; m_target = st; m_brush = sb;

    bool ok = SUCCEEDED(hr);
    HRESULT chr = E_FAIL;
    if (ok) {
        D2D1_BITMAP_PROPERTIES1 cprops = D2D1::BitmapProperties1(
            D2D1_BITMAP_OPTIONS_CPU_READ | D2D1_BITMAP_OPTIONS_CANNOT_DRAW, pf, 96.0f, 96.0f);
        ID2D1Bitmap1* cpu = nullptr;
        if (SUCCEEDED(ctx->CreateBitmap(size, nullptr, 0, cprops, &cpu)) && cpu) {
            chr = cpu->CopyFromBitmap(nullptr, target, nullptr);
            if (SUCCEEDED(chr)) {
                D2D1_MAPPED_RECT mapped = {};
                if (SUCCEEDED(cpu->Map(D2D1_MAP_OPTIONS_READ, &mapped))) {
                    out_bgra->assign(static_cast<size_t>(width) * height * 4, 0);
                    const size_t row = static_cast<size_t>(width) * 4;
                    for (int y = 0; y < height; ++y)
                        memcpy(out_bgra->data() + static_cast<size_t>(y) * row,
                               mapped.bits + static_cast<size_t>(y) * mapped.pitch, row);
                    cpu->Unmap();
                } else { ok = false; }
            } else { ok = false; }
            cpu->Release();
        } else { ok = false; }
    }

    if (brush) brush->Release();
    if (target) target->Release();
    ctx->Release();
    return ok;
}

} // namespace bar
} // namespace taskpin
