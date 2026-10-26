/*
 * Registers SalatWidget with the XFCE panel using the official macro.
 *
 * The panel looks up the exported function `xfce_panel_module_construct`. A Rust
 * cdylib only exports Rust symbols, so the macro's function is renamed here and
 * re-exported under its real name from lib.rs. The construct function itself
 * (salatwidget_plugin_construct) is implemented in Rust.
 */
#define xfce_panel_module_construct salatwidget_shim_module_construct

#include <libxfce4panel/libxfce4panel.h>

void salatwidget_plugin_construct (XfcePanelPlugin *plugin);

XFCE_PANEL_PLUGIN_REGISTER (salatwidget_plugin_construct);
