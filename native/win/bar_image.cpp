// ============================================================================
//  TaskPin bar — image decode for the Direct2D surface (implementation)
// ============================================================================
#include "bar_image.h"
#include "bar_embed.h"   // bar_log

#include <wincodec.h>
#include <winhttp.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <string>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_BMP
#define STBI_ONLY_GIF
#define STBI_NO_STDIO
#include "lib/stb_image.h"

namespace taskpin {
namespace bar {

// --------------------------------------------------------------- cache ------
namespace {

constexpr int kCacheMax    = 32;   // lib/image.h IMG_CACHE_MAX
constexpr int kMaxFrames   = 64;   // lib/image.h IMG_MAX_FRAMES
constexpr int kMaxBytes    = 4 * 1024 * 1024;

struct CacheEntry {
    std::string key;
    int w = 0, h = 0;
    bool animated = false;
    // Premultiplied BGRA, one buffer per frame.
    std::vector<std::vector<uint8_t>> frames;
    std::vector<int> delays;       // ms per frame
    DWORD start_tick = 0;
    // Lazily built device bitmaps, valid only for the generation they were
    // built under (a D2D device loss invalidates every bitmap).
    std::vector<ID2D1Bitmap*> bitmaps;
    uint64_t bitmap_gen = 0;
};

std::vector<CacheEntry> g_cache;
CRITICAL_SECTION        g_cs;
bool                    g_cs_ready = false;
uint64_t                g_generation = 1;

void EnsureCs() {
    if (!g_cs_ready) { InitializeCriticalSection(&g_cs); g_cs_ready = true; }
}

// Drop every device-dependent bitmap (called when the D2D device is recreated).
void DropBitmapsLocked() {
    for (CacheEntry& e : g_cache) {
        for (ID2D1Bitmap* b : e.bitmaps) if (b) b->Release();
        e.bitmaps.clear();
        e.bitmap_gen = 0;
    }
}

// UTF-8 -> wide, and the reverse, for image sources coming from Lua spans.
std::string WideToUtf8(const wchar_t* w) {
    if (!w || !w[0]) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
    if (n <= 1) return std::string();
    std::string s(static_cast<size_t>(n - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, w, -1, s.data(), n, nullptr, nullptr);
    return s;
}

// ---------------------------------------------------------- base64 ----------
int B64Val(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

std::vector<uint8_t> Base64Decode(const char* s, size_t n) {
    std::vector<uint8_t> out;
    out.reserve(n * 3 / 4 + 4);
    int acc = 0, bits = 0;
    for (size_t i = 0; i < n; ++i) {
        if (s[i] == '=') break;
        int v = B64Val(s[i]);
        if (v < 0) continue;          // skip whitespace/newlines
        acc = (acc << 6) | v;
        bits += 6;
        if (bits >= 8) { bits -= 8; out.push_back(static_cast<uint8_t>((acc >> bits) & 0xFF)); }
    }
    return out;
}

// --------------------------------------------------------- winhttp GET ------
// Minimal synchronous GET, mirroring lib/httputil.c's blocking contract.
std::vector<uint8_t> HttpGet(const wchar_t* url) {
    std::vector<uint8_t> out;
    URL_COMPONENTS uc{};
    uc.dwStructSize = sizeof(uc);
    wchar_t host[256] = {0}, path[2048] = {0};
    uc.lpszHostName = host;   uc.dwHostNameLength = 255;
    uc.lpszUrlPath  = path;   uc.dwUrlPathLength  = 2047;
    if (!WinHttpCrackUrl(url, 0, 0, &uc)) return out;

    HINTERNET hS = WinHttpOpen(L"TaskPin/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                               WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hS) return out;
    WinHttpSetTimeouts(hS, 4000, 4000, 4000, 8000);

    HINTERNET hC = WinHttpConnect(hS, host, uc.nPort, 0);
    if (hC) {
        DWORD flags = (uc.nScheme == INTERNET_SCHEME_HTTPS) ? WINHTTP_FLAG_SECURE : 0;
        HINTERNET hR = WinHttpOpenRequest(hC, L"GET", path, nullptr,
                                          WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
        if (hR && WinHttpSendRequest(hR, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                                     WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
            WinHttpReceiveResponse(hR, nullptr)) {
            DWORD avail = 0;
            do {
                avail = 0;
                if (!WinHttpQueryDataAvailable(hR, &avail) || avail == 0) break;
                if (out.size() + avail > kMaxBytes) break;
                size_t off = out.size();
                out.resize(off + avail);
                DWORD read = 0;
                if (!WinHttpReadData(hR, out.data() + off, avail, &read)) { out.resize(off); break; }
                out.resize(off + read);
            } while (avail > 0);
        }
        if (hR) WinHttpCloseHandle(hR);
        WinHttpCloseHandle(hC);
    }
    WinHttpCloseHandle(hS);
    return out;
}

// ------------------------------------------------------------ file read -----
std::vector<uint8_t> ReadFileBytes(const char* utf8_path) {
    std::vector<uint8_t> out;
    wchar_t wpath[MAX_PATH] = {0};
    MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, wpath, MAX_PATH);
    FILE* f = _wfopen(wpath, L"rb");
    if (!f) { // fall back to the raw byte path (ANSI)
        f = fopen(utf8_path, "rb");
        if (!f) return out;
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz > 0 && sz <= kMaxBytes) {
        out.resize(static_cast<size_t>(sz));
        size_t rd = fread(out.data(), 1, out.size(), f);
        out.resize(rd);
    }
    fclose(f);
    return out;
}

// --------------------------------------------------------- pixel convert ----
// RGBA -> premultiplied BGRA (what D2D wants for B8G8R8A8_UNORM + premultiplied).
std::vector<uint8_t> ToPremulBgra(const uint8_t* rgba, int w, int h) {
    std::vector<uint8_t> dst(static_cast<size_t>(w) * h * 4);
    for (int i = 0; i < w * h; ++i) {
        uint8_t r = rgba[i * 4 + 0], g = rgba[i * 4 + 1];
        uint8_t b = rgba[i * 4 + 2], a = rgba[i * 4 + 3];
        dst[i * 4 + 0] = static_cast<uint8_t>(b * a / 255);
        dst[i * 4 + 1] = static_cast<uint8_t>(g * a / 255);
        dst[i * 4 + 2] = static_cast<uint8_t>(r * a / 255);
        dst[i * 4 + 3] = a;
    }
    return dst;
}

// Nearest-neighbour resize on premultiplied BGRA (matches lib/image.c's simple
// resize so animated and static images scale identically).
std::vector<uint8_t> Resize(const std::vector<uint8_t>& src, int sw, int sh, int dw, int dh) {
    if (sw == dw && sh == dh) return src;
    std::vector<uint8_t> dst(static_cast<size_t>(dw) * dh * 4);
    for (int y = 0; y < dh; ++y) {
        int sy = y * sh / dh;
        for (int x = 0; x < dw; ++x) {
            int sx = x * sw / dw;
            memcpy(&dst[(static_cast<size_t>(y) * dw + x) * 4],
                   &src[(static_cast<size_t>(sy) * sw + sx) * 4], 4);
        }
    }
    return dst;
}

bool IsGif(const std::vector<uint8_t>& d) {
    return d.size() >= 6 &&
           (memcmp(d.data(), "GIF89a", 6) == 0 || memcmp(d.data(), "GIF87a", 6) == 0);
}

void MakeKey(const char* src, int w, int h, std::string& out) {
    char buf[64];
    snprintf(buf, sizeof(buf), "|%d|%d", w, h);
    out.assign(src);
    out += buf;
}

CacheEntry* FindLocked(const std::string& key) {
    for (CacheEntry& e : g_cache) if (e.key == key) return &e;
    return nullptr;
}

void EvictLocked() {
    if (g_cache.empty()) return;
    CacheEntry& e = g_cache.front();
    for (ID2D1Bitmap* b : e.bitmaps) if (b) b->Release();
    g_cache.erase(g_cache.begin());
}

// Decode raw bytes into a cache entry (static or animated).
bool DecodeInto(const std::vector<uint8_t>& raw, int req_w, int req_h, CacheEntry& e) {
    if (IsGif(raw)) {
        int* delays = nullptr;
        int w = 0, h = 0, frames = 0, comp = 0;
        stbi_uc* px = stbi_load_gif_from_memory(raw.data(), static_cast<int>(raw.size()),
                                                &delays, &w, &h, &frames, &comp, 4);
        if (px && frames > 0) {
            int dw = req_w > 0 ? req_w : w;
            int dh = req_h > 0 ? req_h : h;
            int n = frames > kMaxFrames ? kMaxFrames : frames;
            e.animated = n > 1;
            e.w = dw; e.h = dh;
            for (int i = 0; i < n; ++i) {
                const uint8_t* frame = px + static_cast<size_t>(i) * w * h * 4;
                std::vector<uint8_t> bgra = ToPremulBgra(frame, w, h);
                e.frames.push_back(Resize(bgra, w, h, dw, dh));
                e.delays.push_back(delays ? delays[i] : 100);
            }
            stbi_image_free(px);
            if (delays) stbi_image_free(delays);
            return true;
        }
        if (px) stbi_image_free(px);
        if (delays) stbi_image_free(delays);
        // fall through to static decode if the GIF parse failed
    }

    int w = 0, h = 0, ch = 0;
    stbi_uc* px = stbi_load_from_memory(raw.data(), static_cast<int>(raw.size()), &w, &h, &ch, 4);
    if (!px) return false;
    int dw = req_w > 0 ? req_w : w;
    int dh = req_h > 0 ? req_h : h;
    std::vector<uint8_t> bgra = ToPremulBgra(px, w, h);
    stbi_image_free(px);
    e.animated = false;
    e.w = dw; e.h = dh;
    e.frames.push_back(Resize(bgra, w, h, dw, dh));
    e.delays.push_back(0);
    return true;
}

ID2D1Bitmap* BuildBitmap(ID2D1DeviceContext* ctx, const std::vector<uint8_t>& bgra,
                         int w, int h) {
    D2D1_BITMAP_PROPERTIES1 props = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_NONE,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
    ID2D1Bitmap1* bmp1 = nullptr;
    HRESULT hr = ctx->CreateBitmap(D2D1::SizeU(static_cast<UINT32>(w), static_cast<UINT32>(h)),
                                   bgra.data(), static_cast<UINT32>(w) * 4, props, &bmp1);
    if (FAILED(hr) || !bmp1) return nullptr;
    // ID2D1Bitmap1 derives from ID2D1Bitmap; return the base pointer (the
    // caller only draws with it). Keep the single reference.
    return static_cast<ID2D1Bitmap*>(bmp1);
}

int CurrentFrameIndex(const CacheEntry& e) {
    if (!e.animated || e.frames.size() <= 1) return 0;
    int total = 0;
    for (int d : e.delays) total += d > 0 ? d : 100;
    if (total <= 0) total = static_cast<int>(e.frames.size()) * 100;
    int pos = static_cast<int>((GetTickCount() - e.start_tick) % static_cast<DWORD>(total));
    int acc = 0;
    for (size_t i = 0; i < e.delays.size(); ++i) {
        acc += e.delays[i] > 0 ? e.delays[i] : 100;
        if (pos < acc) return static_cast<int>(i);
    }
    return 0;
}

} // namespace

// ------------------------------------------------------------- public -------

void BarImageInit() {
    EnsureCs();
    EnterCriticalSection(&g_cs);
    g_cache.clear();
    g_generation = 1;
    LeaveCriticalSection(&g_cs);
}

void BarImageShutdown() {
    if (!g_cs_ready) return;
    EnterCriticalSection(&g_cs);
    for (CacheEntry& e : g_cache)
        for (ID2D1Bitmap* b : e.bitmaps) if (b) b->Release();
    g_cache.clear();
    LeaveCriticalSection(&g_cs);
}

ID2D1Bitmap* BarImageGet(ID2D1DeviceContext* ctx, const char* source,
                         int req_w, int req_h, int* out_w, int* out_h) {
    if (!source || !source[0] || !ctx) return nullptr;
    EnsureCs();

    std::string key;
    MakeKey(source, req_w, req_h, key);

    // Fast path: cache hit with bitmaps valid for the current generation.
    EnterCriticalSection(&g_cs);
    CacheEntry* hit = FindLocked(key);
    if (hit && hit->bitmap_gen == g_generation && !hit->bitmaps.empty()) {
        int idx = CurrentFrameIndex(*hit);
        if (idx >= 0 && idx < static_cast<int>(hit->bitmaps.size()) && hit->bitmaps[idx]) {
            if (out_w) *out_w = hit->w;
            if (out_h) *out_h = hit->h;
            ID2D1Bitmap* b = hit->bitmaps[idx];
            LeaveCriticalSection(&g_cs);
            return b;
        }
    }
    // Cache hit but bitmaps belong to a dead device: drop them, rebuild below.
    if (hit) {
        for (ID2D1Bitmap* b : hit->bitmaps) if (b) b->Release();
        hit->bitmaps.clear();
        hit->bitmap_gen = 0;
    }
    LeaveCriticalSection(&g_cs);

    // Load raw bytes.
    std::vector<uint8_t> raw;
    if (strncmp(source, "data:", 5) == 0) {
        const char* comma = strchr(source, ',');
        if (comma) raw = Base64Decode(comma + 1, strlen(comma + 1));
    } else if (strncmp(source, "http://", 7) == 0 || strncmp(source, "https://", 8) == 0) {
        wchar_t wurl[2048] = {0};
        MultiByteToWideChar(CP_UTF8, 0, source, -1, wurl, 2048);
        raw = HttpGet(wurl);
    } else {
        raw = ReadFileBytes(source);
    }
    if (raw.empty()) return nullptr;

    // Decode outside the lock (stb decode can be slow).
    CacheEntry entry;
    entry.key = key;
    if (!DecodeInto(raw, req_w, req_h, entry)) return nullptr;
    entry.start_tick = GetTickCount();

    // Insert + build the current frame's bitmap.
    EnterCriticalSection(&g_cs);
    CacheEntry* slot = FindLocked(key);
    if (!slot) {
        if (g_cache.size() >= kCacheMax) EvictLocked();
        g_cache.push_back(CacheEntry());
        slot = &g_cache.back();
        *slot = std::move(entry);
    }
    slot->bitmaps.assign(slot->frames.size(), nullptr);
    int idx = CurrentFrameIndex(*slot);
    ID2D1Bitmap* bmp = BuildBitmap(ctx, slot->frames[idx], slot->w, slot->h);
    if (bmp) {
        slot->bitmaps[idx] = bmp;
        slot->bitmap_gen = g_generation;
    }
    ID2D1Bitmap* result = bmp;
    if (out_w) *out_w = slot->w;
    if (out_h) *out_h = slot->h;
    LeaveCriticalSection(&g_cs);
    return result;
}

bool BarImageIsAnimated(const char* source, int req_w, int req_h) {
    if (!source || !source[0]) return false;
    EnsureCs();
    std::string key;
    MakeKey(source, req_w, req_h, key);
    EnterCriticalSection(&g_cs);
    CacheEntry* e = FindLocked(key);
    bool r = e && e->animated;
    LeaveCriticalSection(&g_cs);
    return r;
}

ID2D1Bitmap* BarImageGet(ID2D1DeviceContext* ctx, const wchar_t* source,
                         int req_w, int req_h, int* out_w, int* out_h) {
    std::string u8 = WideToUtf8(source);
    return BarImageGet(ctx, u8.c_str(), req_w, req_h, out_w, out_h);
}

bool BarImageIsAnimated(const wchar_t* source, int req_w, int req_h) {
    std::string u8 = WideToUtf8(source);
    return BarImageIsAnimated(u8.c_str(), req_w, req_h);
}

void BarImageOnDeviceLost() {
    if (!g_cs_ready) return;
    EnterCriticalSection(&g_cs);
    DropBitmapsLocked();
    g_generation++;
    LeaveCriticalSection(&g_cs);
    bar_log("image: device lost -> dropped cached bitmaps (generation=%llu)",
            (unsigned long long)g_generation);
}

} // namespace bar
} // namespace taskpin
