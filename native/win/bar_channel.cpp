// ============================================================================
//  TaskPin bar — the `taskpin/bar` MethodChannel
// ============================================================================
//  Dart (`lib/core/bar/bar_controller.dart`) owns WHAT to show; this file owns
//  the native surfaces. The contract is deliberately small:
//
//    Dart -> native
//      setSpans(barId, spans, width, x, title, autoIndex)
//                                 create-or-update one bar; creates the window
//                                 and embeds it on first call. `autoIndex`
//                                 is the bar's position among the pinned
//                                 items, or -1 when it is explicitly placed.
//      setGeometry(barId, width, x, autoIndex)
//                                 clamp + move/resize (no persist)
//      setStyle(barId, style)     colours, font size, state stripe, scroll
//      remove(barId)              tear one bar down
//      removeAll()                tear every bar down
//      reembedAll()               re-parent after an explorer restart
//
//  AUTO POSITIONING. `bar_x < 0` used to mean "auto", but the old code derived
//  the auto x from `order_`, the order in which windows were CREATED. Bar ids
//  are config indices, so reordering items in the manager left every bar at its
//  old slot and the taskbar showed the wrong content at overlapping widths.
//  `autoIndex` is now the ordering key: Dart sends the index among the PINNED
//  items (0 = left-most in config order) and native sorts by it. Every change
//  that can affect tiling (a bar added/removed, an autoIndex or width changed,
//  the wheel resized a bar) runs one RelayoutAuto() pass over the whole set, so
//  no step depends on creation order or on which bar happened to trigger it.
//  An explicitly positioned bar (`autoIndex < 0`, `x >= 0`) is never moved by
//  that pass.
//
//    native -> Dart (same channel, invoked BY the plugin)
//      onClick        { barId }
//      onWheel        { barId, delta, shift, width, x }
//      onContextMenu  { barId, action: 'unpin' | 'manage' | 'exit' }
//      onHoverChange  { barId, hover }
//
//  ==========================================================================
//  THREADING — the part the plan calls out as fragile
//  ==========================================================================
//  "native→Dart 从插件 registrar 在 UI 线程发很简单，而从 Win32 消息循环回调进
//   Dart 才是脆弱的部分。"
//
//  Every bar is a child window of Shell_TrayWnd, but a child window's messages
//  are delivered to the thread that CREATED it, not to its parent's thread.
//  Bars are created here, in a MethodChannel handler, which Flutter runs on the
//  platform thread — so BarWindow::WndProc already runs there. That is a
//  property of how the windows are made, not something this file can see.
//
//  So the events are not sent from the WndProc at all. They are POSTED to a
//  message-only window owned by this plugin, and sent from its window
//  procedure. Two things fall out of that:
//
//    1. The channel send happens on the platform thread even if a future
//       caller creates a bar from somewhere else — PostMessage crosses threads
//       and the target window's procedure always runs on its owner thread.
//    2. It is never sent re-entrantly from inside a message dispatch, which is
//       what makes "call into Dart from a WndProc" fragile in the first place.
//
//  The plugin is registered with `AddPlugin`, so it is destroyed BEFORE the
//  registrar's messenger (PluginRegistrarWindows' destructor calls
//  ClearPlugins() first). Holding the raw messenger pointer is therefore safe
//  for the plugin's whole lifetime.
// ============================================================================

// Included UNCONDITIONALLY: outside TASKPIN_FLUTTER_PLUGIN the header is the
// only thing that forward-declares `flutter::PluginRegistrarWindows`, which the
// no-op `TaskpinBarRegisterWithRegistrar` below still names. Including it
// inside the #ifdef made the standalone MinGW build fail to compile.
#include "bar_channel.h"

#ifdef TASKPIN_FLUTTER_PLUGIN

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <algorithm>
#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "bar_embed.h"
#include "bar_image.h"
#include "bar_types.h"
#include "bar_window.h"

namespace taskpin {
namespace bar {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr UINT kBarEventMessage = WM_APP + 0x51;

// --------------------------------------------------------------- parsing ----

const EncodableValue* Find(const EncodableMap& m, const char* key) {
    const auto it = m.find(EncodableValue(std::string(key)));
    return it == m.end() ? nullptr : &it->second;
}

int IntArg(const EncodableMap& m, const char* key, int fallback) {
    const EncodableValue* v = Find(m, key);
    if (!v) return fallback;
    if (const auto* i = std::get_if<int32_t>(v)) return *i;
    if (const auto* i = std::get_if<int64_t>(v)) return static_cast<int>(*i);
    if (const auto* d = std::get_if<double>(v)) return static_cast<int>(*d);
    return fallback;
}

bool BoolArg(const EncodableMap& m, const char* key, bool fallback) {
    const EncodableValue* v = Find(m, key);
    if (!v) return fallback;
    if (const auto* b = std::get_if<bool>(v)) return *b;
    return fallback;
}

/// A colour arrives as an ARGB int (0xAARRGGBB), which is exactly the
/// representation `bar_tokens.h` uses, so no byte reordering is needed. The
/// sentinel 0xFFFFFFFF means "use the default", mirroring lib/config.c.
bool ColorArg(const EncodableMap& m, const char* key, uint32_t* out) {
    const EncodableValue* v = Find(m, key);
    if (!v) return false;
    int64_t raw = 0;
    if (const auto* i32 = std::get_if<int32_t>(v)) raw = *i32;
    else if (const auto* i64 = std::get_if<int64_t>(v)) raw = *i64;
    else return false;
    *out = static_cast<uint32_t>(raw);
    return true;
}

/// UTF-8 string arg. Flutter encodes a Dart `String` as UTF-8 bytes in a
/// `std::string`, which is what `Span::text` wants.
std::string StringArg(const EncodableMap& m, const char* key) {
    const EncodableValue* v = Find(m, key);
    if (!v) return std::string();
    if (const auto* s = std::get_if<std::string>(v)) return *s;
    return std::string();
}

/// UTF-8 -> UTF-16 for the wide `Span::text` / image source.
std::wstring Widen(const std::string& utf8) {
    if (utf8.empty()) return std::wstring();
    const int need = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                         static_cast<int>(utf8.size()), nullptr, 0);
    if (need <= 0) return std::wstring();
    std::wstring out(static_cast<size_t>(need), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                        out.data(), need);
    return out;
}

/// One wire span -> the native `Span`.
///
/// Field names follow the engine's `TPSpan` (which `TpBarSpan` in
/// `packages/taskpin_design` mirrors), so a span can be copied across without a
/// translation layer:
///
///   { text, color, size, align, newline, image, img_w, img_h, tabular }
Span ParseSpan(const EncodableMap& m) {
    Span s;
    s.text = Widen(StringArg(m, "text"));

    uint32_t color = 0xFFFFFFFFu;
    if (ColorArg(m, "color", &color)) s.color = color;

    s.font_size = IntArg(m, "size", 0);
    s.align = IntArg(m, "align", AlignLeft);
    if (s.align < AlignLeft || s.align > AlignCenter) s.align = AlignLeft;
    s.newline = BoolArg(m, "newline", false);
    s.is_image = BoolArg(m, "image", false);
    s.img_w = IntArg(m, "img_w", 0);
    s.img_h = IntArg(m, "img_h", 0);
    s.tabular = BoolArg(m, "tabular", false);
    return s;
}

BarStyle ParseStyle(const EncodableMap& m, const BarStyle& base) {
    BarStyle st = base;
    uint32_t c = 0;
    if (ColorArg(m, "bg", &c)) st.bg = c;
    if (ColorArg(m, "bgHover", &c)) st.bgHover = c;
    if (ColorArg(m, "label", &c)) st.label = c;
    if (ColorArg(m, "value", &c)) st.value = c;
    if (ColorArg(m, "icon", &c)) st.icon = c;

    // `fontSize` is a POINT size, matching `cfg.font_size` (lib/config.c:99).
    st.font_size = IntArg(m, "fontSize", st.font_size);
    st.state = IntArg(m, "state", st.state);
    if (st.state < StateNone || st.state > StateStale) st.state = StateNone;
    st.scroll_enabled = BoolArg(m, "scrollEnabled", st.scroll_enabled);
    st.show_separators = BoolArg(m, "showSeparators", st.show_separators);
    return st;
}

// ------------------------------------------------------------- the event ----

/// A native->Dart event, already reduced to plain data.
///
/// Built on whichever thread observed it and SENT on the platform thread (see
/// the THREADING note), which is why it carries values rather than pointers.
struct BarEvent {
    std::string method;
    EncodableMap args;
};

// ----------------------------------------------------------- the plugin -----

class BarChannelPlugin : public flutter::Plugin, public BarWindowHost {
public:
    explicit BarChannelPlugin(flutter::PluginRegistrarWindows* registrar)
        : registrar_(registrar) {}

    ~BarChannelPlugin() override { Shutdown(); }

    /// Create the marshalling window and the channel. Must run on the platform
    /// thread (the registrar's thread).
    void Init() {
        hinst_ = GetModuleHandleW(nullptr);
        BarWindowRegisterClass(hinst_);
        BarImageInit();
        CreateMarshallerWindow();

        channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
            registrar_->messenger(), "taskpin/bar",
            &flutter::StandardMethodCodec::GetInstance());

        channel_->SetMethodCallHandler(
            [this](const flutter::MethodCall<EncodableValue>& call,
                   std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
                HandleMethod(call, std::move(result));
            });
        bar_log("channel: taskpin/bar registered");
    }

    // ---- BarWindowHost -----------------------------------------------------
    // Called from BarWindow::WndProc, i.e. on the thread that created the bar.

    void OnBarClick(int bar_id, const SpanContent&) override {
        Post("onClick", bar_id);
    }
    void OnBarOpenManager(int bar_id) override {
        Post("onContextMenu", bar_id, {{"action", EncodableValue("manage")}});
    }
    void OnBarUnpin(int bar_id) override {
        Post("onContextMenu", bar_id, {{"action", EncodableValue("unpin")}});
    }
    void OnBarExit() override {
        Post("onContextMenu", -1, {{"action", EncodableValue("exit")}});
    }
    void OnBarRefresh(int bar_id) override {
        // The Dart side owns the refresh cadence (each item has its own
        // interval and its own engine call), so the native timer is not the
        // authority here. Nothing to send.
        (void)bar_id;
    }
    void OnBarGeometryChanged(int bar_id, int width, int x, bool shift) override {
        // A Shift+wheel is an explicit placement: the bar must stop being
        // auto-tiled, or the next RelayoutAuto() would snap it back. A plain
        // wheel is a width change, which moves the auto bars after it.
        if (shift) {
            BarWindow* w = FindBar(bar_id);
            if (w) w->SetAutoPlacement(-1, x);
        }
        RelayoutAuto();
        Post("onWheel", bar_id,
             {{"delta", EncodableValue(0)},   // 0 = geometry-only report
              {"shift", EncodableValue(shift)},
              {"width", EncodableValue(width)},
              {"x", EncodableValue(x)}});
    }
    void OnBarLayoutDirty() override { RelayoutAuto(); }

private:
    // ---- method dispatch ---------------------------------------------------

    void HandleMethod(const flutter::MethodCall<EncodableValue>& call,
                      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const std::string& method = call.method_name();
        const EncodableMap empty;
        const auto* args =
            call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
        const EncodableMap& a = args ? *args : empty;

        if (method == "setSpans") {
            const int id = IntArg(a, "barId", -1);
            const auto* spans = Find(a, "spans");
            if (id < 0 || !spans || !std::holds_alternative<EncodableList>(*spans)) {
                result->Error("bad_args", "setSpans needs barId and spans");
                return;
            }
            SetSpans(id, std::get<EncodableList>(*spans), a);
        } else if (method == "setGeometry") {
            const int id = IntArg(a, "barId", -1);
            auto* w = FindBar(id);
            if (!w) { result->Success(); return; }
            const int width = IntArg(a, "width", -1);
            const int x = IntArg(a, "x", -1);
            // `autoIndex` is optional: an older Dart side sends only
            // width/x, in which case the bar keeps whatever placement mode it
            // was created with.
            const int auto_index = IntArg(a, "autoIndex", w->auto_index());
            w->SetAutoPlacement(auto_index, auto_index < 0 ? x : -1);
            w->SetGeometry(width, auto_index < 0 ? x : -1);
            RelayoutAuto();
        } else if (method == "setStyle") {
            const int id = IntArg(a, "barId", -1);
            auto* w = FindBar(id);
            if (w) w->SetStyle(ParseStyle(a, w->style()));
        } else if (method == "remove") {
            Remove(IntArg(a, "barId", -1));
        } else if (method == "removeAll") {
            RemoveAll();
        } else if (method == "reembedAll") {
            for (auto& kv : bars_) kv.second->ReEmbed();
            // Re-embedding restores each window at its own cfg x; auto bars
            // must then be tiled again as a set, or they would all land on the
            // same anchor.
            RelayoutAuto();
        } else {
            result->NotImplemented();
            return;
        }
        result->Success();
    }

    // ---- bar lifecycle -----------------------------------------------------

    BarWindow* FindBar(int id) {
        const auto it = bars_.find(id);
        return it == bars_.end() ? nullptr : it->second.get();
    }

    void SetSpans(int id, const EncodableList& wire, const EncodableMap& args) {
        BarWindow* w = FindBar(id);
        if (!w) {
            const int width = IntArg(args, "width", 0);
            const std::wstring title = Widen(StringArg(args, "title"));
            const BarStyle style = ParseStyle(args, BarStyle());
            auto owned = std::make_unique<BarWindow>();
            if (!owned->Create(hinst_, this, id, title, width, 0)) {
                bar_log("channel: bar %d Create FAILED", id);
                return;
            }
            w = owned.get();
            w->SetStyle(style);
            bars_.emplace(id, std::move(owned));
        }

        // Placement mode first, so EmbedOne and the relayout below agree.
        // `autoIndex` is optional for compatibility with an older Dart side;
        // without it, x < 0 keeps meaning "auto" but the creation-order
        // fallback is all that is available.
        const int auto_index = IntArg(args, "autoIndex", -1);
        const int x = IntArg(args, "x", -1);
        if (auto_index >= 0) {
            w->SetAutoPlacement(auto_index, -1);
        } else {
            // Explicit (or a pre-autoIndex caller): cfg_x >= 0 is the exact x,
            // and -1 keeps the legacy "first embed is auto" behaviour.
            w->SetAutoPlacement(-1, x);
        }

        SpanContent content;
        for (const EncodableValue& v : wire) {
            if (content.Count() >= kMaxSpans) break;
            if (const auto* m = std::get_if<EncodableMap>(&v)) {
                content.spans.push_back(ParseSpan(*m));
            }
        }
        w->SetContent(content);

        // Embed on first use, or re-embed if the taskbar moved under us.
        if (!w->embedded()) {
            EmbedOne(w);
        } else if (auto_index < 0) {
            w->SetGeometry(IntArg(args, "width", -1), x);
        } else {
            w->SetGeometry(IntArg(args, "width", -1), -1);
        }
        // The set, an ordering key or a width may have changed: re-tile all
        // auto bars in one pass.
        RelayoutAuto();
    }

    /// Place one bar, mirroring `bars_create_all()`'s auto-tiling: an explicit
    /// `bar_x >= 0` wins, otherwise the bar sits left of the tray notify area.
    void EmbedOne(BarWindow* w) {
        const BarTarget target = bar_embed_find_primary();
        if (!target.valid()) {
            bar_log("channel: bar %d no primary taskbar", w->bar_id());
            return;
        }
        const int x = w->is_auto() ? AutoX(target, w) : w->cfg_x();
        w->EmbedInto(target, x, w->cfg_y());
    }

    /// Where [w] belongs among the auto bars, right now.
    ///
    /// Sorted by `autoIndex`, never by `order_`: the ordering key is the one
    /// Dart owns and re-sends after a reorder/pin/unpin.
    int AutoX(const BarTarget& target, const BarWindow* w) const {
        const int anchor = BarWindow::AutoAnchor(target);
        int offset = 0;
        for (const int id : SortedAutoIds()) {
            const auto it = bars_.find(id);
            if (it == bars_.end()) continue;
            if (id == w->bar_id()) break;
            offset += it->second->width() + 2;
        }
        int x = anchor - offset - w->width();
        return x < 0 ? 0 : x;
    }

    /// Auto bars, left-most first. Ties (two bars claiming the same key, which
    /// a stale snapshot can briefly produce) fall back to the id so the order
    /// is still deterministic.
    std::vector<int> SortedAutoIds() const {
        std::vector<int> ids;
        for (const auto& kv : bars_) {
            if (kv.second->is_auto()) ids.push_back(kv.first);
        }
        std::sort(ids.begin(), ids.end(), [this](int a, int b) {
            const int ia = bars_.at(a)->auto_index();
            const int ib = bars_.at(b)->auto_index();
            return ia == ib ? a < b : ia < ib;
        });
        return ids;
    }

    /// Re-tile every auto bar in one pass, in autoIndex order.
    ///
    /// Called after every setSpans/setGeometry and after a native wheel. It is
    /// idempotent (ApplyAutoX returns early when x did not change), so an
    /// unchanged set costs a few comparisons and no SetWindowPos.
    void RelayoutAuto() {
        if (bars_.empty()) return;
        const BarTarget target = bar_embed_find_primary();
        if (!target.valid()) return;
        const int anchor = BarWindow::AutoAnchor(target);
        int offset = 0;
        for (const int id : SortedAutoIds()) {
            BarWindow* w = FindBar(id);
            if (!w) continue;
            w->ApplyAutoX(anchor, offset);
            offset += w->width() + 2;
        }
    }

    void Remove(int id) {
        const auto it = bars_.find(id);
        if (it == bars_.end()) return;
        it->second->Destroy();
        bars_.erase(it);
        // Re-tile the survivors: unpinning leaves no hole.
        RelayoutAuto();
    }

    void RemoveAll() {
        for (auto& kv : bars_) kv.second->Destroy();
        bars_.clear();
    }

    // ---- event marshalling -------------------------------------------------

    void Post(const char* method, int bar_id,
              EncodableMap extra = EncodableMap()) {
        auto* ev = new BarEvent();
        ev->method = method;
        ev->args["barId"] = EncodableValue(bar_id);
        for (auto& kv : extra) ev->args[kv.first] = std::move(kv.second);

        if (!marshaller_ || !PostMessageW(marshaller_, kBarEventMessage, 0,
                                          reinterpret_cast<LPARAM>(ev))) {
            delete ev;   // no platform thread to deliver it: drop, never leak
        }
    }

    void CreateMarshallerWindow() {
        static bool class_registered = false;
        if (!class_registered) {
            WNDCLASSEXW wc = {};
            wc.cbSize = sizeof(wc);
            wc.lpfnWndProc = &BarChannelPlugin::MarshallerProc;
            wc.hInstance = hinst_;
            wc.lpszClassName = L"TaskPinBarChannelMarshaller";
            RegisterClassExW(&wc);
            class_registered = true;
        }
        marshaller_ = CreateWindowExW(0, L"TaskPinBarChannelMarshaller", L"", 0,
                                      0, 0, 0, 0, HWND_MESSAGE, nullptr, hinst_,
                                      this);
        if (!marshaller_) {
            bar_log("channel: marshaller window FAILED err=%lu", GetLastError());
        }
    }

    static LRESULT CALLBACK MarshallerProc(HWND hwnd, UINT msg, WPARAM wp,
                                           LPARAM lp) {
        if (msg == WM_NCCREATE) {
            auto* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
            SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                              reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
            return TRUE;
        }
        auto* self =
            reinterpret_cast<BarChannelPlugin*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
        if (self && msg == kBarEventMessage) {
            std::unique_ptr<BarEvent> ev(reinterpret_cast<BarEvent*>(lp));
            self->Deliver(*ev);
            return 0;
        }
        return DefWindowProcW(hwnd, msg, wp, lp);
    }

    /// Runs on the platform thread, outside any message dispatch.
    void Deliver(const BarEvent& ev) {
        if (!channel_) return;
        channel_->InvokeMethod(
            ev.method,
            std::make_unique<EncodableValue>(EncodableMap(ev.args)));
    }

    void Shutdown() {
        RemoveAll();
        BarImageShutdown();
        if (marshaller_) {
            DestroyWindow(marshaller_);
            marshaller_ = nullptr;
        }
        channel_.reset();
    }

    flutter::PluginRegistrarWindows* registrar_ = nullptr;
    std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
    HWND marshaller_ = nullptr;
    HINSTANCE hinst_ = nullptr;

    /// `barId -> window`. Insertion order is deliberately NOT tracked: the
    /// auto tiling sorts by the `autoIndex` Dart sends, so it survives a
    /// reorder. (It used to keep an `order_` vector and tile by creation
    /// order, which is what made reordering impossible.)
    std::map<int, std::unique_ptr<BarWindow>> bars_;
};

}  // namespace

void BarChannelRegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    if (!registrar) return;
    auto plugin = std::make_unique<BarChannelPlugin>(registrar);
    plugin->Init();
    registrar->AddPlugin(std::move(plugin));
}

}  // namespace bar
}  // namespace taskpin

void TaskpinBarRegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    taskpin::bar::BarChannelRegisterWithRegistrar(registrar);
}

#else  // !TASKPIN_FLUTTER_PLUGIN

// No Flutter in this build (a standalone MinGW build of `native/win`, which
// produces the demo harness). The runner is a different CMake target and does
// not share this define, so the symbol must still exist for a link to succeed.
void TaskpinBarRegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    (void)registrar;
}

#endif  // TASKPIN_FLUTTER_PLUGIN
