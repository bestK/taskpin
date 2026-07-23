#ifndef TASKPIN_UI_COMMON_H
#define TASKPIN_UI_COMMON_H

/*
 * TaskPin UI layout helpers
 * -------------------------
 * Provides reusable form rows, buttons, footer/toolbar bars, and table flags.
 * All visual constants come from ui_theme.h — no raw colors here.
 *
 * Layout contract:
 *   ┌──────────────────────────── content ────────────────────────────┐
 *   │  form / table body  (padding SpaceLg)                           │
 *   │  ...                                                            │
 *   ├─────────────────────────────────────────────────────────────────┤
 *   │  action bar  (height FooterH, buttons left, status right)       │
 *   └─────────────────────────────────────────────────────────────────┘
 */

#include "ui_theme.h"
#include <windows.h>
#include <cstdio>
#include <cstring>

#ifndef TASKPIN_VERSION
#define TASKPIN_VERSION "dev"
#endif

/* ---- Back-compat macros so existing call sites compile without changes ---- */
#define UI_PAD          Theme::SpaceLg
#define UI_GAP          Theme::SpaceSm
#define UI_GAP_SM       Theme::SpaceXs
#define UI_GAP_LG       Theme::SpaceMd
#define UI_LABEL_W      Theme::LabelW
#define UI_LABEL_W_WIDE Theme::LabelWWide
#define UI_BTN_H        Theme::BtnH
#define UI_BTN_W        Theme::BtnW
#define UI_BTN_W_WIDE   Theme::BtnWWide
#define UI_BTN_W_SM     Theme::BtnWSm
#define UI_FOOTER_H     Theme::FooterH
#define UI_TOOLBAR_H    Theme::ToolbarH
#define UI_INPUT_H      Theme::InputH
#define UI_ROW_H        Theme::RowH

/* ---- string helpers ---- */

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

inline void ui_id(char *out, int out_size, const char *prefix, const char *label) {
    std::snprintf(out, (size_t)out_size, "##%s_%s", prefix ? prefix : "f",
        label ? label : "x");
}

/* ---- form rows ---- */

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
    /* Label on left, Input + Button on same line using SameLine. */
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label ? label : "");
    ImGui::SameLine(label_w);

    char id[128];
    ui_id(id, sizeof(id), "tb", label);
    char bid[128];
    ui_id(bid, sizeof(bid), "tbb", label);
    char blabel[160];
    std::snprintf(blabel, sizeof(blabel), "%s%s", btn ? btn : "...", bid);

    float avail = ImGui::GetContentRegionAvail().x;
    float gap = ImGui::GetStyle().ItemSpacing.x;
    float input_w = avail - btn_w - gap - 2.0f; /* 2px safety margin */
    if (input_w < 40.0f) input_w = 40.0f;
    ImGui::SetNextItemWidth(input_w);
    ImGui::InputText(id, buf, (size_t)buf_size);
    ImGui::SameLine(0, gap);
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

/* ---- section / separator ---- */

inline void ui_section_gap(void) {
    ImGui::Dummy(ImVec2(0, UI_GAP));
}

inline void ui_section_sep(void) {
    ImGui::Dummy(ImVec2(0, UI_GAP_SM));
    ImGui::Separator();
    ImGui::Dummy(ImVec2(0, UI_GAP_SM));
}

/* ---- buttons ---- */

inline bool ui_btn(const char *label, float width = UI_BTN_W) {
    return ImGui::Button(label ? label : "", ImVec2(width, UI_BTN_H));
}

inline bool ui_btn_sm(const char *label) {
    return ImGui::Button(label ? label : "", ImVec2(UI_BTN_W_SM, UI_BTN_H));
}

inline int ui_ok_cancel(const char *ok_label, const char *cancel_label) {
    float total = UI_BTN_W * 2 + UI_GAP;
    float x = (ImGui::GetWindowWidth() - total) * 0.5f;
    if (x < UI_PAD) x = UI_PAD;
    ImGui::SetCursorPosX(x);
    int result = 0;
    if (ui_btn(ok_label, UI_BTN_W)) result = 1;
    ImGui::SameLine(0, UI_GAP);
    if (ui_btn(cancel_label, UI_BTN_W)) result = 2;
    /* 按钮下方留白 */
    ImGui::Dummy(ImVec2(0, UI_PAD));
    return result;
}

/* ---- footer / toolbar ---- */

inline void ui_footer_begin(const char *id = "footer") {
    ImGui::PushStyleColor(ImGuiCol_ChildBg, Theme::BgBase);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding,
        ImVec2(UI_PAD, (UI_FOOTER_H - UI_BTN_H) * 0.5f));
    ImGui::BeginChild(id, ImVec2(0.0f, UI_FOOTER_H), true,
        ImGuiWindowFlags_NoScrollbar);
}

inline void ui_footer_end(void) {
    ImGui::EndChild();
    ImGui::PopStyleVar();
    ImGui::PopStyleColor();
}

inline void ui_footer_status(const char *text) {
    if (!text || !text[0]) return;
    ImVec2 size = ImGui::CalcTextSize(text);
    float x = ImGui::GetWindowWidth() - size.x - UI_PAD;
    float cur = ImGui::GetCursorPosX();
    if (x > cur + UI_GAP) {
        ImGui::SameLine(x);
        ImGui::AlignTextToFramePadding();
        ImGui::TextColored(Theme::TextSecondary, "%s", text);
    }
}

inline void ui_toolbar_begin(const char *id = "toolbar") {
    ImGui::PushStyleColor(ImGuiCol_ChildBg, Theme::BgBase);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding,
        ImVec2(UI_PAD, (UI_TOOLBAR_H - UI_BTN_H) * 0.5f));
    ImGui::BeginChild(id, ImVec2(0.0f, UI_TOOLBAR_H), false,
        ImGuiWindowFlags_NoScrollbar);
}

inline void ui_toolbar_end(void) {
    ImGui::EndChild();
    ImGui::PopStyleVar();
    ImGui::PopStyleColor();
}

/* ---- tables ---- */

inline ImGuiTableFlags ui_table_flags(void) {
    return ImGuiTableFlags_Borders |
           ImGuiTableFlags_RowBg |
           ImGuiTableFlags_Resizable |
           ImGuiTableFlags_ScrollY |
           ImGuiTableFlags_SizingFixedFit |
           ImGuiTableFlags_PadOuterX;
}

inline float ui_body_height(void) {
    float h = ImGui::GetContentRegionAvail().y - UI_FOOTER_H - UI_PAD;
    return h < 80.0f ? 80.0f : h;
}

/* ---- back-compat aliases ---- */

inline void ui_label_input(const char *label, char *buf, int buf_size,
    float label_w = UI_LABEL_W, float = 0.0f) {
    ui_field_text(label, buf, buf_size, label_w);
}

inline void ui_label_input_int(const char *label, int *value,
    float label_w = UI_LABEL_W, float input_w = 100.0f) {
    ui_field_int(label, value, label_w, input_w);
}

/* i18n title with fallback */
inline const WCHAR *ui_title(const char *key, const WCHAR *fallback) {
    const WCHAR *t = tr(key);
    if (!t || !t[0]) return fallback ? fallback : L"TaskPin";
    bool looks_like_key = false;
    for (const WCHAR *p = t; *p; p++) {
        if (*p == L'.') { looks_like_key = true; break; }
    }
    if (looks_like_key) return fallback ? fallback : L"TaskPin";
    bool has_printable = false;
    for (const WCHAR *p = t; *p && (p - t) < 100; p++) {
        if (*p >= 0x20 && *p < 0xD800) { has_printable = true; break; }
        if (*p >= 0xE000 && *p < 0xFFFE) { has_printable = true; break; }
    }
    if (!has_printable && fallback && fallback[0]) return fallback;
    return t;
}

#endif
