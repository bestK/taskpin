// ============================================================================
//  TaskPin bar — standalone demo harness
// ============================================================================
//  Creates 3 fake bars with hardcoded span sets and embeds them in the real
//  taskbar, so a human can look at the taskbar and see it working without
//  Flutter.
//
//    bar 0  colour emoji + tabular metric   (proves the DirectWrite colour path)
//    bar 1  CJK text + two colours + right-aligned value (proves font fallback)
//    bar 2  error state + two-line model    (danger stripe + newline)
//
//  Modes:
//    (default)   live demo, embeds in the taskbar, right-click -> Exit, Esc quits
//    --selftest  offscreen render + machine-checkable colour-font assertion;
//                also exercises the watcher's re-embed path WITHOUT touching
//                explorer.exe (test seam). Exits 0 on pass, non-zero on fail.
//
//  IMPORTANT: this harness never kills or restarts explorer.exe.
// ============================================================================
#include "bar_window.h"
#include "bar_embed.h"
#include "bar_render_d2d.h"
#include "bar_image.h"

#include <windows.h>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <string>
#include <vector>
#include <memory>

using namespace taskpin::bar;

namespace {

HINSTANCE g_hinst = nullptr;
bool g_running = true;
int  g_exit_code = 0;

// --------------------------------------------------------------- helpers ----
std::wstring W(const char* utf8) {
    if (!utf8) return L"";
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    if (n <= 1) return L"";
    std::wstring s(static_cast<size_t>(n - 1), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, s.data(), n);
    return s;
}

// A very small state store so the wheel's "persist" behavior is observable.
struct BarState { int width = 200; int x = -1; };
std::vector<BarState> g_state;
const wchar_t* kStateFile = L"native\\win\\build\\demo_state.json";

void SaveState() {
    FILE* f = _wfopen(kStateFile, L"w");
    if (!f) return;
    fputs("{\n  \"bars\": [\n", f);
    for (size_t i = 0; i < g_state.size(); ++i)
        fprintf(f, "    {\"id\": %d, \"width\": %d, \"x\": %d}%s\n",
                static_cast<int>(i), g_state[i].width, g_state[i].x,
                i + 1 < g_state.size() ? "," : "");
    fputs("  ]\n}\n", f);
    fclose(f);
    bar_log("persist: wrote %ls", kStateFile);
}

// --------------------------------------------------------------- host -------
class DemoHost : public BarWindowHost {
public:
    std::vector<std::unique_ptr<BarWindow>>* bars = nullptr;

    void OnBarClick(int bar_id, const SpanContent&) override {
        bar_log("event: bar %d left-click -> click action (host would open dialog/URL)", bar_id);
    }
    void OnBarOpenManager(int bar_id) override {
        bar_log("event: bar %d double-click -> open manager", bar_id);
    }
    void OnBarUnpin(int bar_id) override {
        bar_log("event: bar %d right-click Unpin", bar_id);
    }
    void OnBarExit() override {
        bar_log("event: Exit selected");
        g_running = false;
        PostQuitMessage(0);
    }
    void OnBarRefresh(int bar_id) override {
        bar_log("event: bar %d refresh tick", bar_id);
    }
    void OnBarPersistGeometry(int bar_id, int width, int x) override {
        if (bar_id >= 0 && bar_id < static_cast<int>(g_state.size())) {
            g_state[bar_id].width = width;
            g_state[bar_id].x = x;
            SaveState();
        }
    }
};

// ------------------------------------------------------------ span sets -----

SpanContent MakeEmojiBar() {
    SpanContent c;
    Span s;
    // 🌈 U+1F308 rainbow: spans ~6 distinct saturated hues, so it is a strong
    // proof that the DirectWrite COLOUR FONT path is live (a GDI monochrome
    // coverage mask can produce at most one hue).
    s.text = W("\xF0\x9F\x8C\x88");
    s.font_size = 12;
    s.align = AlignLeft;
    c.spans.push_back(s);

    Span face;
    face.text = W("\xF0\x9F\x98\x80");  // 😀 grinning face
    face.font_size = 12;
    c.spans.push_back(face);

    Span v;
    v.text = L" CPU ";
    v.color = kColorLabel;
    c.spans.push_back(v);

    Span v2;
    v2.text = L"42%";
    v2.color = kColorValue;
    v2.tabular = true;
    c.spans.push_back(v2);

    return c;
}

SpanContent MakeCjkBar() {
    SpanContent c;
    Span a;
    a.text = W("\xE4\xB8\xAD\xE6\x96\x87");  // 中文
    a.color = 0xFF58A6FFu;
    a.align = AlignLeft;
    c.spans.push_back(a);

    Span b;
    b.text = W("\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E");  // 日本語
    b.color = 0xFF3FB950u;
    c.spans.push_back(b);

    Span d;
    d.text = W("\xED\x95\x9C\xEA\xB5\xAD\xEC\x96\xB4");  // 한국어
    d.color = 0xFFD29922u;
    c.spans.push_back(d);

    Span v;
    v.text = L" 12.3 GB";
    v.color = kColorValue;
    v.tabular = true;
    v.align = AlignRight;
    c.spans.push_back(v);
    return c;
}

SpanContent MakeErrorBar() {
    SpanContent c;
    Span line1;
    line1.text = W("\xE2\x9A\xA0");  // ⚠
    line1.color = kColorStateError;
    c.spans.push_back(line1);

    Span t;
    t.text = L" fetch failed";
    t.color = kColorStateError;
    c.spans.push_back(t);

    // Second line (the newline/two-line model).
    Span nl;
    nl.newline = true;
    nl.text = L"retry in 30s";
    nl.color = kColorLabel;
    c.spans.push_back(nl);
    return c;
}

// ------------------------------------------------------- colour analysis ----
// Count distinct saturated hues in a BGRA buffer. Used by --selftest to prove
// the DirectWrite COLOUR FONT path is live: a colour emoji yields several
// distinct saturated hues, whereas GDI's monochrome coverage mask yields one
// (or zero, for pure greyscale text).
struct ChromaReport {
    int saturated_pixels = 0;
    int distinct_hues = 0;
    int max_chroma = 0;
    int colours[12] = {0};
    int colour_count = 0;
};

ChromaReport AnalyzeChroma(const std::vector<uint8_t>& bgra, int w, int h) {
    ChromaReport r;
    bool seen[36] = {false};
    for (int i = 0; i < w * h; ++i) {
        int b = bgra[i * 4 + 0], g = bgra[i * 4 + 1], rr = bgra[i * 4 + 2], a = bgra[i * 4 + 3];
        if (a < 40) continue;
        // Un-premultiply for a fair hue reading.
        if (a > 0 && a < 255) {
            rr = rr * 255 / a; g = g * 255 / a; b = b * 255 / a;
            if (rr > 255) rr = 255; if (g > 255) g = 255; if (b > 255) b = 255;
        }
        int mx = rr > g ? (rr > b ? rr : b) : (g > b ? g : b);
        int mn = rr < g ? (rr < b ? rr : b) : (g < b ? g : b);
        int chroma = mx - mn;
        if (chroma > r.max_chroma) r.max_chroma = chroma;
        if (chroma > 60) {
            r.saturated_pixels++;
            // 10-degree hue buckets (only 36 needed for 360/10).
            int hb = 0;
            if (mx == mn) hb = 0;
            else if (mx == rr) hb = (int)(60.0 * ((g - b) / (double)chroma) + 360) % 360 / 10;
            else if (mx == g)  hb = (int)(60.0 * ((b - rr) / (double)chroma) + 120) / 10;
            else               hb = (int)(60.0 * ((rr - g) / (double)chroma) + 240) / 10;
            if (hb < 0) hb += 36; if (hb >= 36) hb -= 36;
            seen[hb] = true;
        }
    }
    for (int i = 0; i < 36; ++i) if (seen[i]) r.distinct_hues++;
    return r;
}

// ------------------------------------------------------- png dump (WIC) -----
// Write a BGRA buffer to a PNG so a human (or the agent) can inspect the exact
// pixels the renderer produced. Returns false on any failure.
bool DumpPng(IWICImagingFactory* wic, const std::vector<uint8_t>& bgra, int w, int h,
             const wchar_t* path) {
    if (!wic || bgra.empty() || w <= 0 || h <= 0) return false;
    IWICBitmapEncoder* enc = nullptr;
    IWICStream* stream = nullptr;
    IWICBitmapFrameEncode* frame = nullptr;
    IPropertyBag2* props = nullptr;
    bool ok = false;

    if (SUCCEEDED(wic->CreateStream(&stream)) &&
        SUCCEEDED(stream->InitializeFromFilename(path, GENERIC_WRITE)) &&
        SUCCEEDED(wic->CreateEncoder(GUID_ContainerFormatPng, nullptr, &enc)) &&
        SUCCEEDED(enc->Initialize(stream, WICBitmapEncoderNoCache)) &&
        SUCCEEDED(enc->CreateNewFrame(&frame, &props)) &&
        SUCCEEDED(frame->Initialize(props))) {
        frame->SetSize(static_cast<UINT>(w), static_cast<UINT>(h));
        WICPixelFormatGUID fmt = GUID_WICPixelFormat32bppBGRA;
        frame->SetPixelFormat(&fmt);
        if (SUCCEEDED(frame->WritePixels(static_cast<UINT>(h), static_cast<UINT>(w) * 4,
                                         static_cast<UINT>(bgra.size()),
                                         const_cast<BYTE*>(bgra.data()))) &&
            SUCCEEDED(frame->Commit()) && SUCCEEDED(enc->Commit())) {
            ok = true;
        }
    }
    if (props) props->Release();
    if (frame) frame->Release();
    if (enc) enc->Release();
    if (stream) stream->Release();
    return ok;
}

// Composite several bar renders into one image (vertically stacked) so a single
// PNG shows everything the demo draws.
bool DumpComposite(IWICImagingFactory* wic, const std::vector<std::vector<uint8_t>>& imgs,
                   int w, int bar_h, const wchar_t* path) {
    if (imgs.empty()) return false;
    const int total_h = bar_h * static_cast<int>(imgs.size());
    std::vector<uint8_t> out(static_cast<size_t>(w) * total_h * 4, 0);
    for (size_t i = 0; i < imgs.size(); ++i) {
        const size_t row = static_cast<size_t>(w) * 4;
        if (imgs[i].size() < row * bar_h) continue;
        memcpy(out.data() + static_cast<size_t>(i) * bar_h * row, imgs[i].data(), row * bar_h);
    }
    return DumpPng(wic, out, w, total_h, path);
}

// ------------------------------------------------------------- selftest -----

int RunSelfTest() {
    bar_log("=== selftest ===");
    int failures = 0;

    D2DGlobals g;
    if (!D2DGlobalsInit(&g)) {
        bar_log("SELFTEST FAIL: D2D/DWrite/WIC globals not created");
        return 1;
    }
    bar_log("SELFTEST: factories ok  d2d=%p dwrite=%p dwrite2=%p wic=%p d3d=%p d2d_device=%p",
            (void*)g.d2d, (void*)g.dwrite, (void*)g.dwrite2, (void*)g.wic,
            (void*)g.d3d, (void*)g.d2d_device);
    if (!g.d2d)        { bar_log("SELFTEST FAIL: ID2D1Factory1 null"); ++failures; }
    if (!g.dwrite)     { bar_log("SELFTEST FAIL: IDWriteFactory null"); ++failures; }
    if (!g.d2d_device) { bar_log("SELFTEST FAIL: ID2D1Device null"); ++failures; }
    if (!g.wic)        { bar_log("SELFTEST FAIL: IWICImagingFactory null"); ++failures; }
    if (!g.dwrite2)    bar_log("SELFTEST WARN: IDWriteFactory2 null (CJK fallback via DW default)");

    // --- render the emoji bar offscreen and assert colour glyphs ---
    const int W_PX = 220, H_PX = 40;
    SpanContent emoji = MakeEmojiBar();
    BarStyle style;
    style.bg = 0xFF0E1116u;   // opaque so un-premultiply is exact

    BarRenderer renderer;
    std::vector<uint8_t> px;
    if (!renderer.RenderOffscreen(&g, emoji, style, W_PX, H_PX, &px)) {
        bar_log("SELFTEST FAIL: RenderOffscreen returned false");
        ++failures;
    } else {
        ChromaReport r = AnalyzeChroma(px, W_PX, H_PX);
        bar_log("SELFTEST: emoji render %dx%d -> saturated_px=%d distinct_hues=%d max_chroma=%d",
                W_PX, H_PX, r.saturated_pixels, r.distinct_hues, r.max_chroma);
        if (r.saturated_pixels < 20) {
            bar_log("SELFTEST FAIL: too few saturated pixels (%d) — colour font path likely dead",
                    r.saturated_pixels);
            ++failures;
        }
        if (r.distinct_hues < 3) {
            bar_log("SELFTEST FAIL: only %d distinct saturated hue(s) — expected >= 3 "
                    "(a GDI monochrome mask would give 0-1)", r.distinct_hues);
            ++failures;
        } else {
            bar_log("SELFTEST PASS: colour emoji produced %d distinct saturated hues "
                    "-> DirectWrite colour-font path is LIVE", r.distinct_hues);
        }
    }

    // --- CJK fallback: render and assert non-trivial ink coverage ---
    SpanContent cjk = MakeCjkBar();
    std::vector<uint8_t> cpx;
    const int CJK_W = 260;
    if (!renderer.RenderOffscreen(&g, cjk, style, CJK_W, H_PX, &cpx)) {
        bar_log("SELFTEST FAIL: CJK RenderOffscreen returned false");
        ++failures;
    } else {
        int ink = 0;
        for (int i = 0; i < CJK_W * H_PX; ++i) if (cpx[i * 4 + 3] > 40) ++ink;
        bar_log("SELFTEST: CJK render -> ink pixels=%d", ink);
        if (ink < 200) { bar_log("SELFTEST FAIL: CJK text produced too little ink (%d)", ink); ++failures; }
        else bar_log("SELFTEST PASS: CJK glyphs rendered (font fallback working)");
    }

    // --- error bar (danger stripe + two-line model) ---
    SpanContent errc = MakeErrorBar();
    BarStyle errstyle;
    errstyle.state = StateError;
    std::vector<uint8_t> epx;
    const int ERR_W = 180;
    if (!renderer.RenderOffscreen(&g, errc, errstyle, ERR_W, H_PX, &epx)) {
        bar_log("SELFTEST FAIL: error-bar RenderOffscreen returned false");
        ++failures;
    } else {
        // The 2px left stripe must be danger red (0xF85149 -> B=0x49,G=0x51,R=0xF8).
        int b = epx[0], gg = epx[1], rr = epx[2], aa = epx[3];
        bar_log("SELFTEST: error stripe pixel0 = R=%d G=%d B=%d A=%d", rr, gg, b, aa);
        if (!(rr > 200 && gg < 120 && b < 120)) {
            bar_log("SELFTEST FAIL: left state stripe is not danger red");
            ++failures;
        } else {
            bar_log("SELFTEST PASS: error state stripe rendered in danger red");
        }
    }

    // --- dump PNGs so the render can be inspected without a live taskbar ---
    {
        // Render all three at the same width so they can be stacked.
        std::vector<std::vector<uint8_t>> imgs;
        std::vector<uint8_t> e2, c2, x2;
        if (renderer.RenderOffscreen(&g, MakeEmojiBar(), style, CJK_W, H_PX, &e2)) imgs.push_back(e2);
        if (renderer.RenderOffscreen(&g, MakeCjkBar(), style, CJK_W, H_PX, &c2)) imgs.push_back(c2);
        if (renderer.RenderOffscreen(&g, MakeErrorBar(), errstyle, CJK_W, H_PX, &x2)) imgs.push_back(x2);
        const wchar_t* out = L"native\\win\\build\\selftest_bars.png";
        if (!imgs.empty() && DumpComposite(g.wic, imgs, CJK_W, H_PX, out))
            bar_log("SELFTEST: wrote %ls (emoji / CJK / error bars stacked)", out);
        else
            bar_log("SELFTEST WARN: could not write PNG evidence");
    }

    // --- watcher test seam: prove detect -> re-embed fires WITHOUT explorer ---
    {
        struct Host : BarWindowHost {
            int reembeds = 0;
            int persists = 0;
            int last_w = 0, last_x = 0;
            void OnBarClick(int, const SpanContent&) override {}
            void OnBarOpenManager(int) override {}
            void OnBarUnpin(int) override {}
            void OnBarExit() override {}
            void OnBarRefresh(int) override {}
            void OnBarPersistGeometry(int, int w, int x) override {
                persists++; last_w = w; last_x = x;
            }
        } host;

        BarWindow bar;
        if (!BarWindowRegisterClass(g_hinst)) {
            bar_log("SELFTEST FAIL: RegisterClassExW failed");
            ++failures;
        } else if (!bar.Create(g_hinst, &host, 99, L"selftest", 120, 32)) {
            bar_log("SELFTEST FAIL: bar Create failed");
            ++failures;
        } else {
            BarTarget t = bar_embed_find_primary();
            if (!t.valid()) {
                bar_log("SELFTEST WARN: no primary taskbar; skipping embed assertions");
            } else {
                bool ok = bar.EmbedInto(t, -1, -1);
                bar_log("SELFTEST: embed ok=%d rect=(%d,%d %dx%d) dpi=%u",
                        ok ? 1 : 0, bar.geometry().x, bar.geometry().y,
                        bar.geometry().w, bar.geometry().h, t.dpi);
                if (!ok) { bar_log("SELFTEST FAIL: EmbedInto returned false"); ++failures; }

                // --- wheel parity: width += 5 clamped 50..800, persists ---
                bar.TestWheel(120, false);   // +5
                int w_after_up = bar.width();
                bar_log("SELFTEST: wheel up -> width=%d (expect 125)", w_after_up);
                if (w_after_up != 125) { bar_log("SELFTEST FAIL: wheel up width != 125"); ++failures; }
                bar.TestWheel(-120, false);  // -5
                int w_after_down = bar.width();
                bar_log("SELFTEST: wheel down -> width=%d (expect 120)", w_after_down);
                if (w_after_down != 120) { bar_log("SELFTEST FAIL: wheel down width != 120"); ++failures; }
                if (host.persists < 2) {
                    bar_log("SELFTEST FAIL: wheel did not persist (persists=%d)", host.persists);
                    ++failures;
                } else {
                    bar_log("SELFTEST PASS: wheel width +/-5 and persisted (w=%d x=%d)",
                            host.last_w, host.last_x);
                }

                // --- clamp at the lower bound ---
                for (int i = 0; i < 40; ++i) bar.TestWheel(-120, false);
                bar_log("SELFTEST: 40x wheel down -> width=%d (expect clamp 50)", bar.width());
                if (bar.width() != 50) { bar_log("SELFTEST FAIL: width not clamped to 50"); ++failures; }
                // --- clamp at the upper bound ---
                for (int i = 0; i < 200; ++i) bar.TestWheel(120, false);
                bar_log("SELFTEST: 200x wheel up -> width=%d (expect clamp 800)", bar.width());
                if (bar.width() != 800) { bar_log("SELFTEST FAIL: width not clamped to 800"); ++failures; }
                if (bar.width() == 50 || bar.width() == 800)
                    bar_log("SELFTEST PASS: width clamped to 50..800");

                // --- Shift+wheel moves X, clamped inside the taskbar ---
                int x_before = bar.x();
                bar.TestWheel(120, true);    // shift: x -= 10
                int x_after = bar.x();
                bar_log("SELFTEST: shift+wheel up -> x %d -> %d (expect -10)", x_before, x_after);
                if (x_after != x_before - 10) { bar_log("SELFTEST FAIL: shift+wheel x step != 10"); ++failures; }
                // Drive x hard left (enough steps to cross any real taskbar) and
                // assert the clamp.
                for (int i = 0; i < 400; ++i) bar.TestWheel(120, true);
                bar_log("SELFTEST: 400x shift+wheel up -> x=%d (expect clamp 0)", bar.x());
                if (bar.x() != 0) { bar_log("SELFTEST FAIL: shift+wheel x not clamped to 0"); ++failures; }
                else bar_log("SELFTEST PASS: shift+wheel moved X and clamped to the taskbar");

                // --- hover state ---
                bar_log("SELFTEST: hover initial=%d", bar.hover() ? 1 : 0);

                // --- transparency: alpha < 255 must create a WS_EX_LAYERED
                //     window (the bit is creation-time only for child windows,
                //     so we destroy + recreate with the semi-transparent style).
                {
                    BarStyle semi;
                    semi.bg = 0x800E1116u;  // alpha 128
                    bar.SetStyle(semi);     // triggers destroy + recreate
                    bool is_layered =
                        (GetWindowLongPtrW(bar.hwnd(), GWL_EXSTYLE) & WS_EX_LAYERED) != 0;
                    bar_log("SELFTEST: bg alpha=%d -> WS_EX_LAYERED=%d (expect 1), renderer.layered=%d",
                            semi.BgAlpha(), is_layered ? 1 : 0, bar.renderer().layered() ? 1 : 0);
                    if (!is_layered) {
                        bar_log("SELFTEST FAIL: alpha<255 did not enable WS_EX_LAYERED");
                        ++failures;
                    } else {
                        bar_log("SELFTEST PASS: alpha<255 uses WS_EX_LAYERED + UpdateLayeredWindow");
                    }
                    // Opaque again: the flag must come back off.
                    BarStyle opaque;
                    bar.SetStyle(opaque);
                    bool still_layered =
                        (GetWindowLongPtrW(bar.hwnd(), GWL_EXSTYLE) & WS_EX_LAYERED) != 0;
                    bar_log("SELFTEST: bg alpha=%d -> WS_EX_LAYERED=%d (expect 0)",
                            opaque.BgAlpha(), still_layered ? 1 : 0);
                    if (still_layered) {
                        bar_log("SELFTEST FAIL: opaque bg did not clear WS_EX_LAYERED");
                        ++failures;
                    } else {
                        bar_log("SELFTEST PASS: alpha==255 keeps an opaque child");
                    }
                }

                TaskbarWatcher watcher;
                watcher.Start(nullptr, [&]() { host.reembeds++; bar.ReEmbed(); });
                // Inject a bogus tracked handle so PollNow() sees a change. This
                // exercises the real detect->re-embed path; explorer is NOT touched.
                watcher.InjectTrackedHandleForTest(reinterpret_cast<HWND>(0xDEADBEEF));
                DWORD t0 = GetTickCount();
                bool fired = watcher.PollNow();
                DWORD dt = GetTickCount() - t0;
                bar_log("SELFTEST: watcher PollNow fired=%d in %lums (reembed_count=%d)",
                        fired ? 1 : 0, (unsigned long)dt, watcher.reembed_count());
                if (!fired || watcher.reembed_count() < 1) {
                    bar_log("SELFTEST FAIL: watcher did not fire on handle change");
                    ++failures;
                } else {
                    bar_log("SELFTEST PASS: watcher detected taskbar change and re-embedded "
                            "(recovery path exercised; real explorer restart still UNVERIFIED)");
                }
                watcher.Stop();
            }
            bar.Destroy();
        }
    }

    D2DGlobalsRelease(&g);
    bar_log("=== selftest %s (%d failure(s)) ===", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}

// -------------------------------------------------------------- live demo ---

// A hidden message-only window that hosts the watcher's poll timer, so the
// 2s taskbar poll runs on the message loop.
LRESULT CALLBACK PollHostProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_TIMER && wp == kTaskbarPollTimerId) {
        auto* w = reinterpret_cast<TaskbarWatcher*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
        if (w) w->PollNow();
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

HWND CreatePollHost() {
    static bool reg = false;
    if (!reg) {
        WNDCLASSEXW wc = {};
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = PollHostProc;
        wc.hInstance = g_hinst;
        wc.lpszClassName = L"TaskPinBarPollHost";
        RegisterClassExW(&wc);
        reg = true;
    }
    return CreateWindowExW(0, L"TaskPinBarPollHost", L"", 0, 0, 0, 0, 0,
                           HWND_MESSAGE, nullptr, g_hinst, nullptr);
}

int RunDemo() {
    bar_log("=== demo ===");

    BarWindowRegisterClass(g_hinst);

    std::vector<BarTarget> targets = bar_embed_enum_targets();
    bar_log("targets: %d taskbar(s) found", (int)targets.size());
    for (size_t i = 0; i < targets.size(); ++i) {
        const BarTarget& t = targets[i];
        bar_log("  target[%d]: hwnd=%p class=%s notify=%p dpi=%u height=%d rect=(%d,%d %dx%d)",
                (int)i, (void*)t.taskbar, t.primary ? "Shell_TrayWnd" : "Shell_SecondaryTrayWnd",
                (void*)t.notify, t.dpi, t.height,
                t.client_rect.left, t.client_rect.top,
                t.client_rect.right - t.client_rect.left,
                t.client_rect.bottom - t.client_rect.top);
    }
    if (targets.empty()) {
        bar_log("FATAL: no Shell_TrayWnd found");
        return 2;
    }
    const BarTarget primary = targets[0];
    const int bar_h = primary.height > 0 ? primary.height : kHeightWin10;

    DemoHost host;
    std::vector<std::unique_ptr<BarWindow>> bars;
    host.bars = &bars;

    struct Spec { SpanContent content; BarStyle style; int width; };
    std::vector<Spec> specs;
    specs.push_back({ MakeEmojiBar(),  BarStyle(), 150 });
    specs.push_back({ MakeCjkBar(),    BarStyle(), 220 });
    {
        Spec err;
        err.content = MakeErrorBar();
        err.style.state = StateError;
        err.width = 180;
        specs.push_back(err);
    }
    g_state.assign(specs.size(), BarState());

    // Auto-tile left of the tray, reproducing bars_create_all()'s
    // offset_x += w + 2 so the three bars sit side by side like today.
    // Anchor = left edge of TrayNotifyWnd (or the taskbar's right edge).
    int anchor_x;
    {
        RECT nrc = {};
        if (primary.notify && GetWindowRect(primary.notify, &nrc)) {
            POINT p = { nrc.left, nrc.top };
            ScreenToClient(primary.taskbar, &p);
            anchor_x = p.x;
        } else {
            anchor_x = primary.client_rect.right;
        }
    }
    // Compute each bar's x so they tile to the left of the anchor. Bar 0 is the
    // right-most, matching the plan's "left of the notification area".
    std::vector<int> xs(specs.size(), 0);
    {
        int right = anchor_x;
        for (int i = static_cast<int>(specs.size()) - 1; i >= 0; --i) {
            right -= specs[i].width;
            xs[i] = right < 0 ? 0 : right;
            right -= 2;  // 2px gap, matches bars_create_all()
        }
    }

    for (size_t i = 0; i < specs.size(); ++i) {
        auto bar = std::make_unique<BarWindow>();
        if (!bar->Create(g_hinst, &host, static_cast<int>(i),
                         L"TaskPinBar", specs[i].width, bar_h)) {
            bar_log("bar %d: create FAILED, skipping", (int)i);
            continue;
        }
        bar->SetStyle(specs[i].style);
        bar->SetContent(specs[i].content);
        g_state[i].width = specs[i].width;

        if (!bar->EmbedInto(primary, xs[i], -1)) {
            bar_log("bar %d: embed FAILED", (int)i);
        }
        g_state[i].x = bar->x();
        bars.push_back(std::move(bar));
    }
    SaveState();

    // Explorer-restart self-heal watcher. The poll timer is hosted by a
    // message-only window so PollNow() runs on the message loop.
    HWND poll_host = CreatePollHost();
    TaskbarWatcher watcher;
    watcher.Start(poll_host, [&]() {
        bar_log("watcher: re-embedding %d bar(s)", (int)bars.size());
        for (auto& b : bars) b->ReEmbed();
    });
    SetWindowLongPtrW(poll_host, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(&watcher));

    bar_log("demo running: %d bar(s) embedded. Right-click a bar -> Exit, or press Esc.",
            (int)bars.size());

    MSG msg;
    while (g_running && GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if (msg.message == WM_KEYDOWN && msg.wParam == VK_ESCAPE) {
            g_running = false;
            break;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    watcher.Stop();
    if (poll_host) DestroyWindow(poll_host);
    for (auto& b : bars) b->Destroy();
    bar_log("demo exiting");
    return 0;
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    g_hinst = GetModuleHandleW(nullptr);

    bool selftest = false;
    for (int i = 1; i < argc; ++i)
        if (wcscmp(argv[i], L"--selftest") == 0) selftest = true;

    // Console + file logging so the evidence is greppable.
    if (AttachConsole(ATTACH_PARENT_PROCESS) || AllocConsole()) {
        FILE* f = nullptr;
        freopen_s(&f, "CONOUT$", "w", stdout);
        freopen_s(&f, "CONOUT$", "w", stderr);
    }
    bar_log_set_file(L"native\\win\\build\\bar_demo.log");

    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    BarImageInit();

    int rc = selftest ? RunSelfTest() : RunDemo();

    BarImageShutdown();
    CoUninitialize();
    return rc;
}
