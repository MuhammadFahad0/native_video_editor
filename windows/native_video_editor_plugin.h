#ifndef FLUTTER_PLUGIN_NATIVE_VIDEO_EDITOR_PLUGIN_H_
#define FLUTTER_PLUGIN_NATIVE_VIDEO_EDITOR_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <atomic>
#include <functional>
#include <queue>
#include <thread>
#include <vector>

namespace native_video_editor {

class NativeVideoEditorPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  NativeVideoEditorPlugin(flutter::PluginRegistrarWindows *registrar);

  virtual ~NativeVideoEditorPlugin();

  NativeVideoEditorPlugin(const NativeVideoEditorPlugin&) = delete;
  NativeVideoEditorPlugin& operator=(const NativeVideoEditorPlugin&) = delete;

 private:
  void PostTask(std::function<void()> task);
  void ComposeVideo(const flutter::EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void GetMediaInfo(const flutter::EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ReportProgress(const std::string& path, double progress);
  int window_proc_id_ = -1;
  bool shutting_down_ = false;
  std::queue<std::function<void()>> tasks_;
  std::vector<std::thread> workers_;
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void ProcessVideo(
      const flutter::EncodableMap &args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void CancelProcessVideo(
      const flutter::EncodableMap &args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void ExtractThumbnail(
      const flutter::EncodableMap &args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void ComposeImageWithAudio(
      const flutter::EncodableMap &args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void MergeAudioIntoVideo(
      const flutter::EncodableMap &args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::PluginRegistrarWindows *registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::mutex mutex_;
  std::unordered_map<std::string, std::shared_ptr<std::atomic<bool>>> active_cancellations_;
};

}  // namespace native_video_editor

#endif  // FLUTTER_PLUGIN_NATIVE_VIDEO_EDITOR_PLUGIN_H_
