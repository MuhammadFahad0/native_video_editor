#include "include/native_video_editor/native_video_editor_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "native_video_editor_plugin.h"

void NativeVideoEditorPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  native_video_editor::NativeVideoEditorPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
