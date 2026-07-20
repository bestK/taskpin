#include "ui.h"

/*
 * 管理窗口已经由 Dear ImGui 绘制。保留这些 C 接口，供任务栏窗口和
 * 旧的编辑器调用，避免改变核心配置与脚本模块的边界。
 */
void listview_populate(void) {
    modern_ui_refresh();
}

void show_main_window(void) {
    modern_ui_show();
}
