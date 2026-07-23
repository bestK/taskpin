/*
 * TaskPin UI Theme — Design Token System
 * ----------------------------------------
 * All visual constants live here. No business code should use raw ImVec4 / float values.
 *
 * Color reference: JetBrains Darcula / Discord hybrid palette.
 * Spacing reference: 4px grid.
 */
#ifndef TASKPIN_UI_THEME_H
#define TASKPIN_UI_THEME_H

#include "imgui.h"
#include "i18n.h"

/* ---- forward declare for ConfirmModal ---- */
#ifdef __cplusplus
extern "C" { const char *tr8(const char *key); }
#endif

namespace Theme {

/* ============================================================
 * 3.1  Base palette
 * ============================================================ */
inline ImVec4 Hex(float r, float g, float b, float a = 1.0f) {
    return ImVec4(r / 255.0f, g / 255.0f, b / 255.0f, a);
}

/* backgrounds — darkest to lightest */
static const ImVec4 BgBase      = Hex(0x1E, 0x1F, 0x22);   /* #1E1F22  window bg       */
static const ImVec4 BgElevated  = Hex(0x2B, 0x2D, 0x31);   /* #2B2D31  panel / child   */
static const ImVec4 BgInput     = Hex(0x38, 0x3A, 0x40);   /* #383A40  input / combo   */
static const ImVec4 BgHover     = Hex(0x43, 0x45, 0x4D);   /* #43454D  frame hovered   */
static const ImVec4 BgActive    = Hex(0x4E, 0x50, 0x58);   /* #4E5058  frame active    */

/* borders & separators */
static const ImVec4 Border      = Hex(0x3F, 0x41, 0x47);   /* #3F4147                   */

/* text */
static const ImVec4 TextPrimary   = Hex(0xE3, 0xE5, 0xE8); /* #E3E5E8                   */
static const ImVec4 TextSecondary = Hex(0x9B, 0xA1, 0xA6); /* #9BA1A6                   */
static const ImVec4 TextDisabled  = Hex(0x5C, 0x5E, 0x66); /* #5C5E66                   */

/* accent */
static const ImVec4 Accent        = Hex(0x58, 0x65, 0xF2); /* #5865F2  primary action   */
static const ImVec4 AccentHover   = Hex(0x79, 0x83, 0xF5); /* lighter  +8%              */
static const ImVec4 AccentActive  = Hex(0x47, 0x52, 0xC4); /* darker   -12%             */

/* semantic */
static const ImVec4 Success       = Hex(0x3B, 0xA5, 0x5D); /* #3BA55D                   */
static const ImVec4 Warning       = Hex(0xF0, 0xA0, 0x20); /* #F0A020                   */
static const ImVec4 Danger        = Hex(0xE7, 0x4C, 0x3C); /* #E74C3C                   */
static const ImVec4 DangerHover   = Hex(0xC0, 0x39, 0x2B); /* #C0392B                   */
static const ImVec4 DangerActive  = Hex(0x9B, 0x2C, 0x2C); /* #9B2C2C                   */

/* neutral button */
static const ImVec4 BtnFace       = Hex(0x3A, 0x3C, 0x42); /* #3A3C42                   */
static const ImVec4 BtnHover      = Hex(0x48, 0x4A, 0x52); /* #484A52                   */
static const ImVec4 BtnActive     = Hex(0x2E, 0x30, 0x36); /* #2E3036                   */

/* selection / highlight */
static const ImVec4 SelectBg      = ImVec4(0.345f, 0.392f, 0.949f, 0.18f); /* accent @18% */
static const ImVec4 SelectBgHov   = ImVec4(0.345f, 0.392f, 0.949f, 0.28f); /* accent @28% */

/* table */
static const ImVec4 TableRowBg    = BgElevated;
static const ImVec4 TableRowBgAlt = Hex(0x27, 0x29, 0x2C); /* #27292C  subtle zebra     */

/* scrollbar */
static const ImVec4 ScrollBg      = ImVec4(0.08f, 0.08f, 0.08f, 0.50f);
static const ImVec4 ScrollGrab    = Hex(0x50, 0x52, 0x58);
static const ImVec4 ScrollGrabHov = Hex(0x62, 0x64, 0x6A);
static const ImVec4 ScrollGrabAct = Hex(0x74, 0x76, 0x7C);

/* modal */
static const ImVec4 ModalDimBg    = ImVec4(0.0f, 0.0f, 0.0f, 0.55f);

/* ============================================================
 * 5.  Spacing tokens (4px grid)
 * ============================================================ */
static const float SpaceXs   = 4.0f;
static const float SpaceSm   = 8.0f;
static const float SpaceMd   = 12.0f;
static const float SpaceLg   = 16.0f;
static const float SpaceXl   = 24.0f;

/* ============================================================
 * 5.  Rounding
 * ============================================================ */
static const float RoundWindow  = 8.0f;
static const float RoundControl = 4.0f;
static const float RoundPopup   = 8.0f;
static const float RoundScroll  = 6.0f;
static const float RoundGrab    = 4.0f;
static const float RoundTab     = 4.0f;

/* ============================================================
 * Layout tokens (used by ui_common helpers)
 * ============================================================ */
static const float LabelW      = 100.0f;
static const float LabelWWide  = 130.0f;
static const float BtnH        = 30.0f;
static const float BtnW        = 80.0f;
static const float BtnWWide    = 100.0f;
static const float BtnWSm      = 60.0f;
static const float FooterH     = 48.0f;
static const float ToolbarH    = 40.0f;
static const float InputH      = 24.0f;
static const float RowH        = 30.0f;

/* ============================================================
 * Theme::Apply — call once per ImGui context after font setup
 * ============================================================ */
inline void Apply(void) {
    ImGuiStyle &s = ImGui::GetStyle();

    /* geometry */
    s.WindowPadding     = ImVec2(SpaceLg, SpaceLg);
    s.FramePadding      = ImVec2(SpaceMd, 6.0f);
    s.CellPadding       = ImVec2(SpaceSm, 6.0f);
    s.ItemSpacing       = ImVec2(SpaceSm, SpaceSm);
    s.ItemInnerSpacing  = ImVec2(SpaceXs, SpaceXs);
    s.ScrollbarSize     = 14.0f;
    s.GrabMinSize       = 10.0f;
    s.IndentSpacing     = 20.0f;

    /* borders */
    s.WindowBorderSize  = 1.0f;
    s.ChildBorderSize   = 1.0f;
    s.PopupBorderSize   = 1.0f;
    s.FrameBorderSize   = 0.0f;

    /* rounding */
    s.WindowRounding    = RoundWindow;
    s.ChildRounding     = RoundControl;
    s.FrameRounding     = RoundControl;
    s.PopupRounding     = RoundPopup;
    s.ScrollbarRounding = RoundScroll;
    s.GrabRounding      = RoundGrab;
    s.TabRounding       = RoundTab;

    /* colors */
    ImVec4 *c = s.Colors;
    c[ImGuiCol_Text]                  = TextPrimary;
    c[ImGuiCol_TextDisabled]          = TextDisabled;
    c[ImGuiCol_WindowBg]              = BgBase;
    c[ImGuiCol_ChildBg]               = BgElevated;
    c[ImGuiCol_PopupBg]               = BgElevated;
    c[ImGuiCol_Border]                = Border;
    c[ImGuiCol_FrameBg]               = BgInput;
    c[ImGuiCol_FrameBgHovered]        = BgHover;
    c[ImGuiCol_FrameBgActive]         = BgActive;
    c[ImGuiCol_TitleBg]               = Hex(0x18, 0x19, 0x1C);
    c[ImGuiCol_TitleBgActive]         = Hex(0x23, 0x25, 0x29);
    c[ImGuiCol_MenuBarBg]             = BgElevated;
    c[ImGuiCol_ScrollbarBg]           = ScrollBg;
    c[ImGuiCol_ScrollbarGrab]         = ScrollGrab;
    c[ImGuiCol_ScrollbarGrabHovered]  = ScrollGrabHov;
    c[ImGuiCol_ScrollbarGrabActive]   = ScrollGrabAct;
    c[ImGuiCol_CheckMark]             = Accent;
    c[ImGuiCol_SliderGrab]            = Accent;
    c[ImGuiCol_SliderGrabActive]      = AccentActive;
    c[ImGuiCol_Button]                = BtnFace;
    c[ImGuiCol_ButtonHovered]         = BtnHover;
    c[ImGuiCol_ButtonActive]          = BtnActive;
    c[ImGuiCol_Header]                = SelectBg;
    c[ImGuiCol_HeaderHovered]         = SelectBgHov;
    c[ImGuiCol_HeaderActive]          = AccentActive;
    c[ImGuiCol_Separator]             = Border;
    c[ImGuiCol_SeparatorHovered]      = TextSecondary;
    c[ImGuiCol_SeparatorActive]       = TextPrimary;
    c[ImGuiCol_ResizeGrip]            = ImVec4(0.345f, 0.392f, 0.949f, 0.10f);
    c[ImGuiCol_ResizeGripHovered]     = ImVec4(0.345f, 0.392f, 0.949f, 0.30f);
    c[ImGuiCol_ResizeGripActive]      = ImVec4(0.345f, 0.392f, 0.949f, 0.50f);
    c[ImGuiCol_Tab]                   = BgElevated;
    c[ImGuiCol_TabHovered]            = Accent;
    c[ImGuiCol_TabActive]             = AccentActive;
    c[ImGuiCol_TableHeaderBg]         = Hex(0x23, 0x25, 0x29);
    c[ImGuiCol_TableBorderStrong]     = Border;
    c[ImGuiCol_TableBorderLight]      = Hex(0x2E, 0x30, 0x36);
    c[ImGuiCol_TableRowBg]            = TableRowBg;
    c[ImGuiCol_TableRowBgAlt]         = TableRowBgAlt;
    c[ImGuiCol_ModalWindowDimBg]      = ModalDimBg;
}

/* ============================================================
 * Button style helpers — push/pop accent & danger colors
 * ============================================================ */
inline void PushAccentButton(void) {
    ImGui::PushStyleColor(ImGuiCol_Button, Accent);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, AccentHover);
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, AccentActive);
}
inline void PopAccentButton(void) { ImGui::PopStyleColor(3); }

inline void PushDangerButton(void) {
    ImGui::PushStyleColor(ImGuiCol_Button, Danger);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, DangerHover);
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, DangerActive);
}
inline void PopDangerButton(void) { ImGui::PopStyleColor(3); }

inline void PushNeutralButton(void) {
    ImGui::PushStyleColor(ImGuiCol_Button, BtnFace);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, BtnHover);
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, BtnActive);
}
inline void PopNeutralButton(void) { ImGui::PopStyleColor(3); }

/* ============================================================
 * ConfirmModal — reusable delete/confirm popup
 *
 *   static bool open = false;
 *   if (trigger) { open = true; }
 *   int r = Theme::ConfirmModal("Delete?", desc, name, &open);
 *   if (r == 1) { // confirmed }
 * ============================================================ */
inline int ConfirmModal(const char *title, const char *desc,
                        const char *item_name, bool *should_open) {
    if (should_open && *should_open) {
        ImGui::OpenPopup("##confirm_modal");
        *should_open = false;
    }

    int result = 0;

    /* [MOD-4] 局部覆盖弹窗背景色 #2b2b2b，不影响全局主题 */
    ImGui::PushStyleColor(ImGuiCol_PopupBg, ImVec4(0.169f, 0.169f, 0.169f, 0.98f));
    ImGui::PushStyleColor(ImGuiCol_ModalWindowDimBg, ImVec4(0.0f, 0.0f, 0.0f, 0.55f));
    ImGui::PushStyleColor(ImGuiCol_Border, ImVec4(0.25f, 0.25f, 0.25f, 1.0f));

    ImVec2 center = ImGui::GetMainViewport()->GetCenter();
    ImGui::SetNextWindowPos(center, ImGuiCond_Always, ImVec2(0.5f, 0.5f));
    ImGui::SetNextWindowSize(ImVec2(420, 0), ImGuiCond_Always);

    /* 全局 ItemSpacing 设为 (12, 12)，后面局部覆盖标题→描述的间距 */
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(SpaceXl, (float)SpaceLg + 4));
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(SpaceMd, SpaceMd));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 8.0f);  /* 圆角8px */

    if (ImGui::BeginPopupModal("##confirm_modal", NULL,
            ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoMove |
            ImGuiWindowFlags_NoTitleBar)) {

        /* --- 顶部: [!] 图标 + "删除" 标题 --- */
        /* [MOD-4] 局部覆盖危险红色 #e5484d */
        ImVec4 danger_local = ImVec4(0.898f, 0.282f, 0.302f, 1.0f); /* #e5484d */
        ImGui::TextColored(danger_local, "[!]");
        ImGui::SameLine(0, SpaceSm);
        ImGui::TextColored(TextPrimary, "%s", title ? title : "");

        /* [MOD-2] 标题与正文之间间距缩小为 8px */
        ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(SpaceMd, 8.0f));
        ImGui::Dummy(ImVec2(0, 1)); /* 触发缩小后的 ItemSpacing.y */
        ImGui::PopStyleVar();

        /* --- 正文提示 --- */
        if (desc && desc[0])
            ImGui::TextColored(TextSecondary, "%s", desc);

        ImGui::Dummy(ImVec2(0, SpaceXs));

        /* --- 文件名高亮框（只读 InputText，自动完整显示） --- */
        const char *name = (item_name && item_name[0]) ? item_name : "(unnamed)";
        char name_buf[512];
        snprintf(name_buf, sizeof(name_buf), "%s", name);
        ImGui::PushStyleColor(ImGuiCol_FrameBg, BgInput);
        ImGui::PushStyleColor(ImGuiCol_Border, Border);
        ImGui::SetNextItemWidth(-1.0f);
        ImGui::InputText("##cfrm_name", name_buf, sizeof(name_buf),
            ImGuiInputTextFlags_ReadOnly);
        ImGui::PopStyleColor(2);

        /* [MOD-1] 文件名框与 Separator 之间增加 12px 间距 */
        ImGui::Dummy(ImVec2(0, 12.0f));
        ImGui::Separator();
        ImGui::Dummy(ImVec2(0, SpaceMd));

        /* [MOD-3] 按钮等宽：各占可用宽度 45%，中间留间隙 */
        float avail = ImGui::GetContentRegionAvail().x;
        float gap = SpaceMd;                                     /* 12px 间隙 */
        float btn_w = (avail - gap) * 0.45f;                     /* 每个按钮占 45% */
        float btn_h = 36.0f;

        /* 居中偏移 */
        float total = btn_w * 2 + gap;
        float x = (ImGui::GetWindowWidth() - total) * 0.5f;

        /* 取消按钮（中性灰色） */
        ImGui::SetCursorPosX(x);
        PushNeutralButton();
        if (ImGui::Button(tr8("edit.cancel"), ImVec2(btn_w, btn_h)))
            result = 2;
        PopNeutralButton();

        /* 删除按钮（[MOD-4] 局部危险红色 #e5484d） */
        ImGui::SameLine(0, gap);
        ImGui::PushStyleColor(ImGuiCol_Button, danger_local);
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered,
            ImVec4(danger_local.x * 0.85f, danger_local.y * 0.85f, danger_local.z * 0.85f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive,
            ImVec4(danger_local.x * 0.70f, danger_local.y * 0.70f, danger_local.z * 0.70f, 1.0f));
        if (ImGui::Button(title ? title : tr8("main.delete"), ImVec2(btn_w, btn_h)))
            result = 1;
        ImGui::PopStyleColor(3);

        /* 按钮下方留白 */
        ImGui::Dummy(ImVec2(0, 4.0f));

        if (ImGui::IsKeyPressed(ImGuiKey_Escape))
            result = 2;

        if (result != 0)
            ImGui::CloseCurrentPopup();

        ImGui::EndPopup();
    }

    ImGui::PopStyleVar(3);   /* WindowPadding + ItemSpacing + WindowRounding */
    ImGui::PopStyleColor(3); /* PopupBg + ModalDimBg + Border */
    return result;
}

} /* namespace Theme */

#endif /* TASKPIN_UI_THEME_H */
