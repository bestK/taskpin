#ifndef TASKPIN_UI_COMMON_H
#define TASKPIN_UI_COMMON_H

/*
 * TaskPin UI layout system
 * ------------------------
 * Subject: taskbar pin manager for power users.
 * Direction: classic Windows tool chrome — dense, legible, zero decoration.
 *
 * Layout contract used by EVERY management window:
 *
 *   ┌──────────────────────────── content ────────────────────────────┐
 *   │  form / table body  (padding UI_PAD)                            │
 *   │  ...                                                            │
 *   ├─────────────────────────────────────────────────────────────────┤
 *   │  action bar  (height UI_FOOTER_H, buttons left, status right)   │
 *   └─────────────────────────────────────────────────────────────────┘
 *
 * Form rows:
 *   [ label UI_LABEL_W ][ control stretch ]
 *
 * Buttons:
 *   height UI_BTN_H, primary widths UI_BTN_W / UI_BTN_W_WIDE
 */

#include "imgui.h"
#include <windows.h>
#include <cstdio>

#ifndef TASKPIN_VERSION
#define TASKPIN_VERSION "dev"
#endif

/* ---------- palette (classic light tool) ---------- */
static const ImVec4 kBg        = ImVec4(0.941f, 0.941f, 0.941f, 1.0f); /* #F0F0F0 */
static const ImVec4 kPanel     = ImVec4(1.0f, 1.0f, 1.0f, 1.0f);
static const ImVec4 kBorder    = ImVec4(0.675f, 0.675f, 0.675f, 1.0f); /* #ACACAC */
static const ImVec4 kText      = ImVec4(0.0f, 0.0f, 0.0f, 1.0f);
static const ImVec4 kMuted     = ImVec4(0.40f, 0.40f, 0.40f, 1.0f);
static const ImVec4 kHeaderBg  = ImVec4(0.94f, 0.94f, 0.94f, 1.0f);
static const ImVec4 kRowAlt    = ImVec4(0.97f, 0.97f, 0.97f, 1.0f);
static const ImVec4 kSelect    = ImVec4(0.80f, 0.88f, 0.97f, 1.0f); /* system highlight-ish */
static const ImVec4 kBtnFace   = ImVec4(0.88f, 0.88f, 0.88f, 1.0f);
static const ImVec4 kBtnHover  = ImVec4(0.82f, 0.82f, 0.82f, 1.0f);
static const ImVec4 kBtnActive = ImVec4(0.74f, 0.74f, 0.74f, 1.0f);

/* ---------- spacing tokens ---------- */
static const float UI_PAD       = 10.0f;  /* content padding */
static const float UI_GAP       = 8.0f;   /* control gap */
static const float UI_GAP_SM    = 4.0f;
static const float UI_GAP_LG    = 12.0f;
static const float UI_LABEL_W   = 100.0f; /* form label column */
static const float UI_LABEL_W_WIDE = 130.0f;
static const float UI_BTN_H     = 28.0f;
static const float UI_BTN_W     = 72.0f;
static const float UI_BTN_W_WIDE = 88.0f;
static const float UI_BTN_W_SM  = 56.0f;
static const float UI_FOOTER_H  = 44.0f;
static const float UI_TOOLBAR_H = 40.0f;
static const float UI_INPUT_H   = 22.0f;
static const float UI_ROW_H     = 28.0f;  /* label+input row target */

/* ---------- string helpers ---------- */
inline const char *ui_wide_to_utf8(const WCHAR *source, char *dest, int capacity) {
    if (!dest || capacity <= 0) return "";
    dest[0] = '\0';
    if (!source || !source[0]) return dest;
    int length = WideCharToMultiByte(CP_UTF8, 0, source, -1, dest, capacity, NULL, NULL);
    if (length <= 0) {
        dest[0] = '?';
        if (capacity > 1) dest[1] = '\0';
    } else {
        dest[capacity - 1] = '\0';
    }
    return dest;
}

inline void ui_utf8_to_wide(const char *source, WCHAR *dest, int capacity) {
    if (!dest || capacity <= 0) return;
    dest[0] = L'\0';
    if (!source) return;
    MultiByteToWideChar(CP_UTF8, 0, source, -1, dest, capacity);
    dest[capacity - 1] = L'\0';
}

/* Stable ImGui id from a label (avoids collision when labels share text). */
inline void ui_id(char *out, int out_size, const char *prefix, const char *label) {
    std::snprintf(out, (size_t)out_size, "##%s_%s", prefix ? prefix : "f",
        label ? label : "x");
}

/* ---------- form rows ---------- */

/* Label on left (fixed column), control takes remaining width. */
inline void ui_field_begin(const char *label, float label_w = UI_LABEL_W) {
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label ? label : "");
    ImGui::SameLine(label_w);
    ImGui::SetNextItemWidth(-1.0f);
}

inline void ui_field_text(const char *label, char *buf, int buf_size,
    float label_w = UI_LABEL_W) {
    ui_field_begin(label, label_w);
    char id[128];
    ui_id(id, sizeof(id), "t", label);
    ImGui::InputText(id, buf, (size_t)buf_size);
}

inline void ui_field_text_with_button(const char *label, char *buf, int buf_size,
    const char *btn, bool *btn_clicked, float label_w = UI_LABEL_W,
    float btn_w = UI_BTN_W_SM) {
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label ? label : "");
    ImGui::SameLine(label_w);
    float avail = ImGui::GetContentRegionAvail().x;
    float input_w = avail - btn_w - UI_GAP_SM;
    if (input_w < 40.0f) input_w = 40.0f;
    ImGui::SetNextItemWidth(input_w);
    char id[128];
    ui_id(id, sizeof(id), "tb", label);
    ImGui::InputText(id, buf, (size_t)buf_size);
    ImGui::SameLine(0, UI_GAP_SM);
    char bid[128];
    ui_id(bid, sizeof(bid), "tbb", label);
    /* Button text must be unique if multiple "..." exist — use id as label. */
    char blabel[160];
    std::snprintf(blabel, sizeof(blabel), "%s%s", btn ? btn : "...", bid);
    if (ImGui::Button(blabel, ImVec2(btn_w, 0)) && btn_clicked)
        *btn_clicked = true;
}

inline void ui_field_int(const char *label, int *value,
    float label_w = UI_LABEL_W, float input_w = 100.0f) {
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label ? label : "");
    ImGui::SameLine(label_w);
    ImGui::SetNextItemWidth(input_w);
    char id[128];
    ui_id(id, sizeof(id), "i", label);
    ImGui::InputInt(id, value, 0, 0);
}

inline void ui_field_multiline(const char *label, char *buf, int buf_size,
    float height, float label_w = UI_LABEL_W) {
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label ? label : "");
    ImGui::SameLine(label_w);
    ImGui::SetNextItemWidth(-1.0f);
    char id[128];
    ui_id(id, sizeof(id), "m", label);
    ImGui::InputTextMultiline(id, buf, (size_t)buf_size, ImVec2(0, height));
}

inline void ui_field_combo(const char *label, int *current,
    const char *const items[], int count, float label_w = UI_LABEL_W,
    float input_w = 140.0f) {
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label ? label : "");
    ImGui::SameLine(label_w);
    ImGui::SetNextItemWidth(input_w);
    char id[128];
    ui_id(id, sizeof(id), "c", label);
    ImGui::Combo(id, current, items, count);
}

inline void ui_field_check(const char *label, bool *value) {
    ImGui::Checkbox(label ? label : "", value);
}

/* Compact inline fields on one line: label + small input, repeated. */
inline void ui_inline_int(const char *label, int *value, float input_w = 60.0f) {
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label ? label : "");
    ImGui::SameLine(0, UI_GAP_SM);
    ImGui::SetNextItemWidth(input_w);
    char id[128];
    ui_id(id, sizeof(id), "ii", label);
    ImGui::InputInt(id, value, 0, 0);
}

inline void ui_inline_text(const char *label, char *buf, int buf_size, float input_w = 80.0f) {
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label ? label : "");
    ImGui::SameLine(0, UI_GAP_SM);
    ImGui::SetNextItemWidth(input_w);
    char id[128];
    ui_id(id, sizeof(id), "it", label);
    ImGui::InputText(id, buf, (size_t)buf_size);
}

/* ---------- section / separator ---------- */
inline void ui_section_gap(void) {
    ImGui::Dummy(ImVec2(0, UI_GAP));
}

inline void ui_section_sep(void) {
    ImGui::Dummy(ImVec2(0, UI_GAP_SM));
    ImGui::Separator();
    ImGui::Dummy(ImVec2(0, UI_GAP_SM));
}

/* ---------- buttons ---------- */
inline bool ui_btn(const char *label, float width = UI_BTN_W) {
    return ImGui::Button(label ? label : "", ImVec2(width, UI_BTN_H));
}

inline bool ui_btn_sm(const char *label) {
    return ImGui::Button(label ? label : "", ImVec2(UI_BTN_W_SM, UI_BTN_H));
}

/* Centered OK / Cancel pair. Returns 1=OK, 2=Cancel, 0=none. */
inline int ui_ok_cancel(const char *ok_label, const char *cancel_label) {
    float total = UI_BTN_W * 2 + UI_GAP;
    float x = (ImGui::GetWindowWidth() - total) * 0.5f;
    if (x < UI_PAD) x = UI_PAD;
    ImGui::SetCursorPosX(x);
    int result = 0;
    if (ui_btn(ok_label, UI_BTN_W)) result = 1;
    ImGui::SameLine(0, UI_GAP);
    if (ui_btn(cancel_label, UI_BTN_W)) result = 2;
    return result;
}

/* ---------- footer / toolbar bars ---------- */

/* Begin a fixed-height bottom action bar. Caller draws buttons then EndChild. */
inline void ui_footer_begin(const char *id = "footer") {
    ImGui::PushStyleColor(ImGuiCol_ChildBg, kBg);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(UI_PAD, (UI_FOOTER_H - UI_BTN_H) * 0.5f));
    ImGui::BeginChild(id, ImVec2(0.0f, UI_FOOTER_H), true,
        ImGuiWindowFlags_NoScrollbar);
}

inline void ui_footer_end(void) {
    ImGui::EndChild();
    ImGui::PopStyleVar();
    ImGui::PopStyleColor();
}

/* Status text on the right side of current footer/toolbar. */
inline void ui_footer_status(const char *text) {
    if (!text || !text[0]) return;
    ImVec2 size = ImGui::CalcTextSize(text);
    float x = ImGui::GetWindowWidth() - size.x - UI_PAD;
    float cur = ImGui::GetCursorPosX();
    if (x > cur + UI_GAP) {
        ImGui::SameLine(x);
        ImGui::AlignTextToFramePadding();
        ImGui::TextColored(kMuted, "%s", text);
    }
}

/* Top toolbar strip (market source row etc.) */
inline void ui_toolbar_begin(const char *id = "toolbar") {
    ImGui::PushStyleColor(ImGuiCol_ChildBg, kBg);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(UI_PAD, (UI_TOOLBAR_H - UI_BTN_H) * 0.5f));
    ImGui::BeginChild(id, ImVec2(0.0f, UI_TOOLBAR_H), false,
        ImGuiWindowFlags_NoScrollbar);
}

inline void ui_toolbar_end(void) {
    ImGui::EndChild();
    ImGui::PopStyleVar();
    ImGui::PopStyleColor();
}

/* ---------- tables ---------- */
inline ImGuiTableFlags ui_table_flags(void) {
    return ImGuiTableFlags_Borders |
           ImGuiTableFlags_RowBg |
           ImGuiTableFlags_Resizable |
           ImGuiTableFlags_ScrollY |
           ImGuiTableFlags_SizingFixedFit |
           ImGuiTableFlags_PadOuterX;
}

/* Body region above a footer: reserve UI_FOOTER_H. */
inline float ui_body_height(void) {
    float h = ImGui::GetContentRegionAvail().y - UI_FOOTER_H;
    return h < 80.0f ? 80.0f : h;
}

/* Apply classic tool style to current ImGui context. */
inline void ui_apply_style(void) {
    ImGuiStyle &style = ImGui::GetStyle();
    style.WindowPadding = ImVec2(UI_PAD, UI_PAD);
    style.FramePadding = ImVec2(8.0f, 4.0f);
    style.CellPadding = ImVec2(8.0f, 4.0f);
    style.ItemSpacing = ImVec2(UI_GAP, UI_GAP_SM + 2.0f);
    style.ItemInnerSpacing = ImVec2(UI_GAP_SM, UI_GAP_SM);
    style.ScrollbarSize = 14.0f;
    style.WindowBorderSize = 0.0f;
    style.ChildBorderSize = 1.0f;
    style.PopupBorderSize = 1.0f;
    style.FrameBorderSize = 1.0f;
    style.WindowRounding = 0.0f;
    style.ChildRounding = 0.0f;
    style.FrameRounding = 0.0f;
    style.PopupRounding = 0.0f;
    style.ScrollbarRounding = 0.0f;
    style.GrabRounding = 0.0f;
    style.IndentSpacing = UI_PAD;

    ImVec4 *c = style.Colors;
    c[ImGuiCol_Text] = kText;
    c[ImGuiCol_TextDisabled] = kMuted;
    c[ImGuiCol_WindowBg] = kBg;
    c[ImGuiCol_ChildBg] = kPanel;
    c[ImGuiCol_PopupBg] = kPanel;
    c[ImGuiCol_Border] = kBorder;
    c[ImGuiCol_FrameBg] = kPanel;
    c[ImGuiCol_FrameBgHovered] = kBtnHover;
    c[ImGuiCol_FrameBgActive] = kBtnActive;
    c[ImGuiCol_TitleBg] = kBg;
    c[ImGuiCol_TitleBgActive] = kBg;
    c[ImGuiCol_Button] = kBtnFace;
    c[ImGuiCol_ButtonHovered] = kBtnHover;
    c[ImGuiCol_ButtonActive] = kBtnActive;
    c[ImGuiCol_Header] = kSelect;
    c[ImGuiCol_HeaderHovered] = kSelect;
    c[ImGuiCol_HeaderActive] = kSelect;
    c[ImGuiCol_Separator] = kBorder;
    c[ImGuiCol_TableHeaderBg] = kHeaderBg;
    c[ImGuiCol_TableBorderStrong] = kBorder;
    c[ImGuiCol_TableBorderLight] = ImVec4(0.82f, 0.82f, 0.82f, 1.0f);
    c[ImGuiCol_TableRowBg] = kPanel;
    c[ImGuiCol_TableRowBgAlt] = kRowAlt;
    c[ImGuiCol_CheckMark] = kText;
    c[ImGuiCol_ScrollbarBg] = kBg;
    c[ImGuiCol_ScrollbarGrab] = kBorder;
    c[ImGuiCol_ScrollbarGrabHovered] = kMuted;
    c[ImGuiCol_ScrollbarGrabActive] = kMuted;
}

/* Back-compat aliases used by older call sites */
inline void ui_label_input(const char *label, char *buf, int buf_size,
    float label_w = UI_LABEL_W, float /*input_w*/ = 0.0f) {
    ui_field_text(label, buf, buf_size, label_w);
}

inline void ui_label_input_int(const char *label, int *value,
    float label_w = UI_LABEL_W, float input_w = 100.0f) {
    ui_field_int(label, value, label_w, input_w);
}

/* Prefer i18n title; if missing/key-like/empty, use fallback (never empty). */
inline const WCHAR *ui_title(const char *key, const WCHAR *fallback) {
    const WCHAR *t = tr(key);
    /* tr() may return empty, the key itself, or actual translation. */
    if (!t || !t[0]) {
        return fallback ? fallback : L"TaskPin";
    }
    /* If looks like untranslated key (contains '.'), use fallback. */
    bool looks_like_key = false;
    for (const WCHAR *p = t; *p; p++) {
        if (*p == L'.') { looks_like_key = true; break; }
    }
    if (looks_like_key) {
        return fallback ? fallback : L"TaskPin";
    }
    /* Real translation — but might have garbage. Check for basic sanity. */
    bool has_printable = false;
    for (const WCHAR *p = t; *p && (p - t) < 100; p++) {
        if (*p >= 0x20 && *p < 0xD800) { has_printable = true; break; }
        if (*p >= 0xE000 && *p < 0xFFFE) { has_printable = true; break; }
    }
    if (!has_printable && fallback && fallback[0]) {
        return fallback;
    }
    return t;
}

#endif
