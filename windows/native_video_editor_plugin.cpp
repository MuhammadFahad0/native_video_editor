#include "native_video_editor_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Editing.h>
#include <winrt/Windows.Media.Effects.h>
#include <winrt/Windows.Media.Transcoding.h>
#include <winrt/Windows.Media.MediaProperties.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.FileProperties.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <d3d11.h>
#include <dxgi.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <memory>
#include <mutex>
#include <algorithm>
#include <string>
#include <thread>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <cstring>
#include <type_traits>

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Media::Editing;
using namespace winrt::Windows::Media::Effects;
using namespace winrt::Windows::Media::MediaProperties;
using namespace winrt::Windows::Media::Transcoding;
using namespace winrt::Windows::Storage;
using namespace winrt::Windows::Storage::Streams;
using namespace winrt::Windows::Graphics::Imaging;

namespace native_video_editor {

namespace {

constexpr UINT kTaskMessage = WM_APP + 0x39A;
bool NveSamePath(const std::string& a, const std::string& b);

// Flutter replies and channel calls must be delivered on its platform thread.
class PlatformThreadResult : public flutter::MethodResult<flutter::EncodableValue> {
 public:
  PlatformThreadResult(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
      std::function<void(std::function<void()>)> dispatch)
      : result_(std::move(result)), dispatch_(std::move(dispatch)) {}
 protected:
  void SuccessInternal(const flutter::EncodableValue* value) override {
    auto result = result_; auto copy = value ? *value : flutter::EncodableValue();
    dispatch_([result, copy]() { result->Success(copy); });
  }
  void ErrorInternal(const std::string& code, const std::string& message,
      const flutter::EncodableValue* details) override {
    auto result = result_; auto copy = details ? *details : flutter::EncodableValue();
    dispatch_([result, code, message, copy]() { result->Error(code, message, copy); });
  }
  void NotImplementedInternal() override {
    auto result = result_; dispatch_([result]() { result->NotImplemented(); });
  }
 private:
  std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result_;
  std::function<void(std::function<void()>)> dispatch_;
};

std::wstring ToWString(const std::string& str) {
  if (str.empty()) return std::wstring();
  int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
  std::wstring wstr(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstr[0], size_needed);
  return wstr;
}

std::string ToString(const std::wstring& wstr) {
  if (wstr.empty()) return std::string();
  int size_needed = WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), NULL, 0, NULL, NULL);
  std::string str(size_needed, 0);
  WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), &str[0], size_needed, NULL, NULL);
  return str;
}

// Overload: convert winrt::hstring directly
std::string ToString(const winrt::hstring& hstr) {
  return ToString(std::wstring(hstr));
}

const flutter::EncodableValue* GetValue(const flutter::EncodableMap& map, const std::string& key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    return &(it->second);
  }
  return nullptr;
}

std::string GetString(const flutter::EncodableMap& map, const std::string& key) {
  auto val = GetValue(map, key);
  if (val && std::holds_alternative<std::string>(*val)) {
    return std::get<std::string>(*val);
  }
  return "";
}

int64_t GetInt64(const flutter::EncodableMap& map, const std::string& key, int64_t default_val = 0) {
  auto val = GetValue(map, key);
  if (!val) return default_val;
  if (std::holds_alternative<int64_t>(*val)) return std::get<int64_t>(*val);
  if (std::holds_alternative<int32_t>(*val)) return std::get<int32_t>(*val);
  return default_val;
}

int32_t GetInt32(const flutter::EncodableMap& map, const std::string& key, int32_t default_val = 0) {
  auto val = GetValue(map, key);
  if (!val) return default_val;
  if (std::holds_alternative<int32_t>(*val)) return std::get<int32_t>(*val);
  if (std::holds_alternative<int64_t>(*val)) return static_cast<int32_t>(std::get<int64_t>(*val));
  return default_val;
}

double GetDouble(const flutter::EncodableMap& map, const std::string& key, double default_val = 0.0) {
  auto val = GetValue(map, key);
  if (!val) return default_val;
  if (std::holds_alternative<double>(*val)) return std::get<double>(*val);
  if (std::holds_alternative<int32_t>(*val)) return static_cast<double>(std::get<int32_t>(*val));
  if (std::holds_alternative<int64_t>(*val)) return static_cast<double>(std::get<int64_t>(*val));
  return default_val;
}

bool GetBool(const flutter::EncodableMap& map, const std::string& key, bool default_val = false) {
  auto val = GetValue(map, key);
  if (val && std::holds_alternative<bool>(*val)) {
    return std::get<bool>(*val);
  }
  return default_val;
}

// Creates a real writable file at a filesystem path. CreateStreamedFileFromUriAsync
// is for read-only, URI-backed virtual files and cannot be used as a render target.
StorageFile CreateOrReplaceOutputFile(const std::string& output_path) {
  const std::wstring full_path = ToWString(output_path);
  const size_t last_slash = full_path.find_last_of(L"\\/");
  if (last_slash == std::wstring::npos || last_slash + 1 >= full_path.size()) {
    throw hresult_invalid_argument(L"Output path must contain a folder and file name.");
  }

  const std::wstring folder_path = full_path.substr(0, last_slash);
  const std::wstring file_name = full_path.substr(last_slash + 1);
  StorageFolder folder = StorageFolder::GetFolderFromPathAsync(folder_path).get();
  return folder.CreateFileAsync(
      file_name, CreationCollisionOption::ReplaceExisting).get();
}

}  // namespace

void NativeVideoEditorPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "native_video_editor",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<NativeVideoEditorPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  plugin->channel_ = std::move(channel);
  registrar->AddPlugin(std::move(plugin));
}

NativeVideoEditorPlugin::NativeVideoEditorPlugin(flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  // Do NOT call winrt::init_apartment() here — the Flutter UI thread already
  // has a COM apartment (STA). WinRT is initialized per-thread in each worker.
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND, UINT message, WPARAM wparam, LPARAM) -> std::optional<LRESULT> {
        if (message != kTaskMessage || wparam != reinterpret_cast<WPARAM>(this)) return std::nullopt;
        std::queue<std::function<void()>> pending;
        { std::lock_guard<std::mutex> lock(mutex_); pending.swap(tasks_); }
        while (!pending.empty()) { pending.front()(); pending.pop(); }
        return 0;
      });
}

NativeVideoEditorPlugin::~NativeVideoEditorPlugin() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    shutting_down_ = true;
    for (auto& entry : active_cancellations_) entry.second->store(true);
  }
  registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  for (auto& worker : workers_) if (worker.joinable()) worker.join();
}

void NativeVideoEditorPlugin::PostTask(std::function<void()> task) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (shutting_down_) return;
  tasks_.push(std::move(task));
  PostMessage(GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT), kTaskMessage,
      reinterpret_cast<WPARAM>(this), 0);
}

void NativeVideoEditorPlugin::ReportProgress(const std::string& path, double progress) {
  PostTask([this, path, progress]() {
    flutter::EncodableMap args;
    args[flutter::EncodableValue("outputPath")] = flutter::EncodableValue(path);
    args[flutter::EncodableValue("progress")] = flutter::EncodableValue(progress);
    channel_->InvokeMethod("onProgress", std::make_unique<flutter::EncodableValue>(args));
  });
}

void NativeVideoEditorPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Reap finished worker handles without waiting for active exports.
  for (auto& worker : workers_) {
    if (worker.joinable() && WaitForSingleObject(worker.native_handle(), 0) == WAIT_OBJECT_0) worker.join();
  }
  workers_.erase(std::remove_if(workers_.begin(), workers_.end(),
      [](const std::thread& worker) { return !worker.joinable(); }), workers_.end());
  result = std::make_unique<PlatformThreadResult>(std::move(result),
      [this](std::function<void()> task) { PostTask(std::move(task)); });
  const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("invalid_arguments", "Expected argument map.");
    return;
  }

  if (method_call.method_name() == "getMediaInfo") {
    GetMediaInfo(*args, std::move(result));
  } else if (method_call.method_name() == "composeVideo") {
    ComposeVideo(*args, std::move(result));
  } else if (method_call.method_name() == "processVideo") {
    ProcessVideo(*args, std::move(result));
  } else if (method_call.method_name() == "cancelProcessVideo") {
    CancelProcessVideo(*args, std::move(result));
  } else if (method_call.method_name() == "extractThumbnail") {
    ExtractThumbnail(*args, std::move(result));
  } else if (method_call.method_name() == "composeImageWithAudio") {
    ComposeImageWithAudio(*args, std::move(result));
  } else if (method_call.method_name() == "mergeAudioIntoVideo") {
    MergeAudioIntoVideo(*args, std::move(result));
  } else {
    result->NotImplemented();
  }
}

void NativeVideoEditorPlugin::ProcessVideo(
    const flutter::EncodableMap &args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::string input_path = GetString(args, "inputPath");
  std::string output_path = GetString(args, "outputPath");
  int64_t trim_start_ms = GetInt64(args, "trimStartMs", -1);
  int64_t trim_end_ms = GetInt64(args, "trimEndMs", -1);
  int32_t target_width = GetInt32(args, "targetWidth", 0);
  int32_t target_height = GetInt32(args, "targetHeight", 0);
  int32_t rotation_degrees = GetInt32(args, "rotationDegrees", 0);
  double speed_multiplier = GetDouble(args, "speedMultiplier", 1.0);
  bool mute_audio = GetBool(args, "muteAudio", false);

  double crop_left = 0.0, crop_top = 0.0, crop_width = 1.0, crop_height = 1.0;
  bool has_crop = false;
  auto crop_it = args.find(flutter::EncodableValue("cropRect"));
  if (crop_it != args.end() && std::holds_alternative<flutter::EncodableMap>(crop_it->second)) {
    has_crop = true;
    const auto& crop_map = std::get<flutter::EncodableMap>(crop_it->second);
    crop_left = GetDouble(crop_map, "left", 0.0);
    crop_top = GetDouble(crop_map, "top", 0.0);
    crop_width = GetDouble(crop_map, "width", 1.0);
    crop_height = GetDouble(crop_map, "height", 1.0);
  }

  auto cancelled = std::make_shared<std::atomic<bool>>(false);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    active_cancellations_[output_path] = cancelled;
  }

  workers_.emplace_back([this, input_path, output_path, trim_start_ms, trim_end_ms, target_width, target_height, rotation_degrees, speed_multiplier, mute_audio, has_crop, crop_left, crop_top, crop_width, crop_height, cancelled, res = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result))]() mutable {
    winrt::init_apartment();  // Initialize WinRT MTA on this worker thread
    try {
      if (NveSamePath(input_path, output_path)) throw hresult_invalid_argument(L"Output must differ from input.");
      StorageFile input_file = StorageFile::GetFileFromPathAsync(ToWString(input_path)).get();
      MediaClip clip = MediaClip::CreateFromFileAsync(input_file).get();

      if (trim_start_ms >= 0) {
        clip.TrimTimeFromStart(std::chrono::milliseconds(trim_start_ms));
      }
      if (trim_end_ms >= 0) {
        const auto original_duration_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                clip.OriginalDuration()).count();
        const auto trim_from_end_ms =
            std::max<int64_t>(0, original_duration_ms - trim_end_ms);
        clip.TrimTimeFromEnd(std::chrono::milliseconds(trim_from_end_ms));
      }
      if (mute_audio) {
        clip.Volume(0.0);
      }

      bool has_transform = false;
      VideoTransformEffectDefinition transform;

      if (rotation_degrees != 0) {
        has_transform = true;
        switch (rotation_degrees) {
          case 90:
            transform.Rotation(MediaRotation::Clockwise90Degrees);
            break;
          case 180:
            transform.Rotation(MediaRotation::Clockwise180Degrees);
            break;
          case 270:
            transform.Rotation(MediaRotation::Clockwise270Degrees);
            break;
          default:
            throw hresult_invalid_argument(L"Unsupported rotation angle.");
        }
      }

      if (has_crop) {
        has_transform = true;
        auto encodingProps = clip.GetVideoEncodingProperties();
        uint32_t raw_w = encodingProps.Width();
        uint32_t raw_h = encodingProps.Height();

        uint32_t w = raw_w;
        uint32_t h = raw_h;

        auto fileProps = input_file.Properties().GetVideoPropertiesAsync().get();
        auto orientation = fileProps.Orientation();
        if (orientation == winrt::Windows::Storage::FileProperties::VideoOrientation::Rotate90 ||
            orientation == winrt::Windows::Storage::FileProperties::VideoOrientation::Rotate270) {
            w = raw_h;
            h = raw_w;
        }

        float x = static_cast<float>((std::max)(0.0, std::round(crop_left * w)));
        float y = static_cast<float>((std::max)(0.0, std::round(crop_top * h)));
        float cw = static_cast<float>((std::max)(2.0, std::round(crop_width * w)));
        float ch = static_cast<float>((std::max)(2.0, std::round(crop_height * h)));

        if (x + cw > w) cw = static_cast<float>(w) - x;
        if (y + ch > h) ch = static_cast<float>(h) - y;

        int ix = static_cast<int>(x);
        int iy = static_cast<int>(y);
        int icw = static_cast<int>(cw);
        int ich = static_cast<int>(ch);

        if (ix % 2 != 0) ix = (std::max)(0, ix - 1);
        if (iy % 2 != 0) iy = (std::max)(0, iy - 1);
        if (icw % 2 != 0) icw = (std::max)(2, icw - 1);
        if (ich % 2 != 0) ich = (std::max)(2, ich - 1);

        Rect crop(
            static_cast<float>(ix),
            static_cast<float>(iy),
            static_cast<float>(icw),
            static_cast<float>(ich)
        );
        transform.CropRectangle(crop);
      }

      MediaComposition comp;
      comp.Clips().Append(clip);

      StorageFile output_file = CreateOrReplaceOutputFile(output_path);
      MediaEncodingProfile profile = MediaEncodingProfile::CreateMp4(VideoEncodingQuality::HD1080p);

      if (target_width > 0 && target_height > 0) {
        profile.Video().Width(target_width);
        profile.Video().Height(target_height);
      }

      if (mute_audio) profile.Audio(nullptr);
      auto wait_for_export = [&](auto const& operation) {
        operation.Progress([this, output_path, cancelled](auto const& async_info, double progress) {
          if (cancelled->load()) { async_info.Cancel(); return; }
          ReportProgress(output_path, progress / 100.0);
        });
        while (operation.Status() == AsyncStatus::Started) {
          if (cancelled->load()) operation.Cancel();
          std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
        if constexpr (std::is_void_v<decltype(operation.get())>) operation.get();
        else if (operation.get() != TranscodeFailureReason::None) throw hresult_error(E_FAIL, L"Windows could not encode this video.");
      };
      if (has_transform) {
        transform.OutputSize(Size(static_cast<float>(profile.Video().Width()), static_cast<float>(profile.Video().Height())));
        MediaTranscoder transcoder; transcoder.AlwaysReencode(true);
        transcoder.TrimStartTime(clip.TrimTimeFromStart());
        transcoder.TrimStopTime(clip.OriginalDuration() - clip.TrimTimeFromEnd());
        transcoder.AddVideoEffect(transform.ActivatableClassId(), true, transform.Properties());
        auto preparation = transcoder.PrepareFileTranscodeAsync(input_file, output_file, profile).get();
        if (!preparation.CanTranscode()) throw hresult_error(E_FAIL, L"Cannot prepare video edits.");
        wait_for_export(preparation.TranscodeAsync());
      } else {
        wait_for_export(comp.RenderToFileAsync(output_file, MediaTrimmingPreference::Precise, profile));
      }

      {
        std::lock_guard<std::mutex> lock(mutex_);
        active_cancellations_.erase(output_path);
      }

      if (cancelled->load()) {
        res->Error("processing_failed", "Video processing was cancelled.");
      } else {
        res->Success(flutter::EncodableValue(output_path));
      }
    } catch (const hresult_error& ex) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        active_cancellations_.erase(output_path);
      }
      // FIX: ex.message() returns winrt::hstring, convert via std::wstring
      res->Error("processing_failed", ToString(std::wstring(ex.message())));
    } catch (...) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        active_cancellations_.erase(output_path);
      }
      res->Error("processing_failed", "An error occurred during video processing.");
    }
  });
}

void NativeVideoEditorPlugin::CancelProcessVideo(
    const flutter::EncodableMap &args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::string output_path = GetString(args, "outputPath");
  {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = active_cancellations_.find(output_path);
    if (it != active_cancellations_.end()) {
      it->second->store(true);
    }
  }
  result->Success();
}

void NativeVideoEditorPlugin::ExtractThumbnail(
    const flutter::EncodableMap &args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::string input_path = GetString(args, "inputPath");
  std::string output_path = GetString(args, "outputPath");
  int64_t position_ms = GetInt64(args, "positionMs", 0);
  int32_t quality = GetInt32(args, "quality", 90);

  workers_.emplace_back([input_path, output_path, position_ms, quality, res = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result))]() mutable {
    winrt::init_apartment();  // Initialize WinRT MTA on this worker thread
    try {
      if (NveSamePath(input_path, output_path)) throw hresult_invalid_argument(L"Output must differ from input.");
      StorageFile input_file = StorageFile::GetFileFromPathAsync(ToWString(input_path)).get();
      MediaClip clip = MediaClip::CreateFromFileAsync(input_file).get();
      MediaComposition comp;
      comp.Clips().Append(clip);

      ImageStream stream = comp.GetThumbnailAsync(
          std::chrono::milliseconds(position_ms),
          0, 0,
          VideoFramePrecision::NearestFrame).get();

      StorageFile output_file = CreateOrReplaceOutputFile(output_path);
      IRandomAccessStream output_stream = output_file.OpenAsync(FileAccessMode::ReadWrite).get();

      BitmapDecoder decoder = BitmapDecoder::CreateAsync(stream).get();
      SoftwareBitmap bitmap = decoder.GetSoftwareBitmapAsync().get();

      // FIX: Guid is winrt::guid; BitmapEncoder::JpegEncoderId() returns winrt::guid
      winrt::guid encoder_id = BitmapEncoder::JpegEncoderId();
      if (output_path.length() >= 4 && output_path.substr(output_path.length() - 4) == ".png") {
        encoder_id = BitmapEncoder::PngEncoderId();
      }

      BitmapEncoder encoder = BitmapEncoder::CreateAsync(encoder_id, output_stream).get();
      encoder.SetSoftwareBitmap(bitmap);

      if (encoder_id == BitmapEncoder::JpegEncoderId()) {
        BitmapPropertySet property_set;
        BitmapTypedValue quality_val(box_value(static_cast<float>(quality) / 100.0f), PropertyType::Single);
        property_set.Insert(L"ImageQuality", quality_val);
        encoder.BitmapProperties().SetPropertiesAsync(property_set).get();
      }

      encoder.FlushAsync().get();
      res->Success(flutter::EncodableValue(output_path));
    } catch (const hresult_error& ex) {
      res->Error("thumbnail_failed", ToString(std::wstring(ex.message())));
    } catch (...) {
      res->Error("thumbnail_failed", "An error occurred during thumbnail extraction.");
    }
  });
}

void NativeVideoEditorPlugin::ComposeImageWithAudio(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  using V = flutter::EncodableValue;
  flutter::EncodableMap clip, audio, settings, request;
  clip[V("path")] = V(GetString(args, "imagePath"));
  clip[V("isImage")] = V(true);
  clip[V("durationMs")] = V(GetInt64(args, "audioDurationMs", INT64_MAX));
  clip[V("capToAudio")] = V(GetString(args, "audioPath"));
  clip[V("fit")] = V("contain");
  audio[V("path")] = V(GetString(args, "audioPath"));
  settings[V("width")] = V(GetInt32(args, "targetWidth"));
  settings[V("height")] = V(GetInt32(args, "targetHeight"));
  settings[V("frameRate")] = V(GetInt32(args, "frameRate", 30));
  settings[V("videoBitrate")] = V(4000000); settings[V("audioBitrate")] = V(128000);
  request[V("outputPath")] = V(GetString(args, "outputPath"));
  request[V("settings")] = V(settings);
  request[V("clips")] = V(flutter::EncodableList{V(clip)});
  request[V("audioTracks")] = V(flutter::EncodableList{V(audio)});
  ComposeVideo(request, std::move(result));
}

void NativeVideoEditorPlugin::MergeAudioIntoVideo(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  using V = flutter::EncodableValue;
  flutter::EncodableMap clip, audio, settings, request;
  clip[V("path")] = V(GetString(args, "inputVideoPath"));
  clip[V("capToAudio")] = V(GetString(args, "audioPath"));
  clip[V("volume")] = V(GetBool(args, "replaceExistingAudio", true) ? 0.0 : 1.0);
  audio[V("path")] = V(GetString(args, "audioPath"));
  settings[V("width")] = V(0); settings[V("height")] = V(0);
  settings[V("frameRate")] = V(30);
  settings[V("videoBitrate")] = V(4000000); settings[V("audioBitrate")] = V(128000);
  request[V("outputPath")] = V(GetString(args, "outputPath"));
  request[V("settings")] = V(settings);
  request[V("clips")] = V(flutter::EncodableList{V(clip)});
  request[V("audioTracks")] = V(flutter::EncodableList{V(audio)});
  ComposeVideo(request, std::move(result));
}
namespace {
const flutter::EncodableMap& NveMap(const flutter::EncodableMap& map, const char* key) {
  auto value = GetValue(map, key);
  if (!value || !std::holds_alternative<flutter::EncodableMap>(*value))
    throw hresult_invalid_argument(L"Missing object in composition request.");
  return std::get<flutter::EncodableMap>(*value);
}
flutter::EncodableList NveList(const flutter::EncodableMap& map, const char* key) {
  auto value = GetValue(map, key);
  return value && std::holds_alternative<flutter::EncodableList>(*value)
      ? std::get<flutter::EncodableList>(*value) : flutter::EncodableList();
}
int64_t NveMilliseconds(TimeSpan value) {
  return std::chrono::duration_cast<std::chrono::milliseconds>(value).count();
}
bool NveSamePath(const std::string& a, const std::string& b) {
  auto first = std::filesystem::weakly_canonical(ToWString(a)).wstring();
  auto second = std::filesystem::weakly_canonical(ToWString(b)).wstring();
  return CompareStringOrdinal(first.c_str(), -1, second.c_str(), -1, TRUE) == CSTR_EQUAL;
}
int64_t NveSegment(const flutter::EncodableMap& source, int64_t original) {
  const auto start = GetInt64(source, "trimStartMs", 0);
  const auto remaining = original - start;
  const auto duration = (std::min)(remaining, GetInt64(source, "durationMs", remaining));
  if (start < 0 || duration <= 0) throw hresult_invalid_argument(L"Invalid source trim range.");
  return duration;
}
void NveTrim(MediaClip const& clip, const flutter::EncodableMap& source, int64_t limit) {
  const auto start = GetInt64(source, "trimStartMs", 0);
  const auto duration = (std::min)(limit, NveSegment(source, NveMilliseconds(clip.OriginalDuration())));
  clip.TrimTimeFromStart(std::chrono::milliseconds(start));
  clip.TrimTimeFromEnd(std::chrono::milliseconds(NveMilliseconds(clip.OriginalDuration()) - start - duration));
}

// Position is top-left based. Contain shrinks the destination, cover crops the
// source, and stretch maps the source directly to the destination rectangle.
Rect NveFit(MediaClip& clip, const flutter::EncodableMap& source, Rect destination,
    std::vector<std::filesystem::path>& temporary, const std::shared_ptr<std::atomic<bool>>& cancelled) {
  double width = 0, height = 0;
  const bool image = GetBool(source, "isImage") || GetString(source, "type") == "image";
  if (image) {
    // Image clips have no video encoding properties. Read their decoded size.
    auto file = StorageFile::GetFileFromPathAsync(ToWString(GetString(source, "path"))).get();
    auto stream = file.OpenAsync(FileAccessMode::Read).get();
    auto decoder = BitmapDecoder::CreateAsync(stream).get();
    width = decoder.OrientedPixelWidth(); height = decoder.OrientedPixelHeight();
  } else {
    auto properties = clip.GetVideoEncodingProperties();
    width = properties.Width(); height = properties.Height();
  }
  if (width <= 0 || height <= 0) throw hresult_invalid_argument(L"Cannot determine video dimensions.");
  VideoTransformEffectDefinition transform;
  bool has_transform = false;
  const auto fit = GetString(source, "fit");
  if (fit == "contain" || fit.empty()) {
    const double scale = (std::min)(destination.Width / width, destination.Height / height);
    const float out_width = static_cast<float>(width * scale);
    const float out_height = static_cast<float>(height * scale);
    destination.X += (destination.Width - out_width) / 2;
    destination.Y += (destination.Height - out_height) / 2;
    destination.Width = out_width; destination.Height = out_height;
  } else if (fit == "cover") {
    const double aspect = destination.Width / destination.Height;
    double cropped_width = width, cropped_height = height;
    if (width / height > aspect) cropped_width = height * aspect;
    else cropped_height = width / aspect;
    if (!image && (std::abs(cropped_width - width) > 0.5 || std::abs(cropped_height - height) > 0.5)) {
      transform.CropRectangle(Rect(static_cast<float>((width - cropped_width) / 2),
        static_cast<float>((height - cropped_height) / 2),
        static_cast<float>(cropped_width), static_cast<float>(cropped_height)));
      has_transform = true;
    }
  }
  const bool flip_x = GetBool(source, "flipHorizontal"), flip_y = GetBool(source, "flipVertical");
  if (!image && (flip_x || flip_y)) {
    transform.Mirror(static_cast<MediaMirroringOptions>((flip_x ? 1 : 0) | (flip_y ? 2 : 0)));
    has_transform = true;
  }
  if (has_transform) {
    transform.OutputSize(Size(static_cast<float>((std::max)(2, static_cast<int>(destination.Width) / 2 * 2)),
        static_cast<float>((std::max)(2, static_cast<int>(destination.Height) / 2 * 2))));
    transform.PaddingColor(winrt::Windows::UI::Color{255, 0, 0, 0});
    // VideoTransformEffectDefinition belongs to MediaTranscoder. Applying it
    // directly to a MediaClip fails when MediaComposition renders that clip.
    GUID id; winrt::check_hresult(CoCreateGuid(&id)); wchar_t name[64]; StringFromGUID2(id, name, 64);
    auto temporary_path = std::filesystem::temp_directory_path() / (std::wstring(L"nve-transform-") + name + L".mp4");
    temporary.push_back(temporary_path);
    auto input = StorageFile::GetFileFromPathAsync(ToWString(GetString(source, "path"))).get();
    auto output = CreateOrReplaceOutputFile(ToString(temporary_path.wstring()));
    auto profile = MediaEncodingProfile::CreateMp4(VideoEncodingQuality::HD720p);
    profile.Video().Width(static_cast<uint32_t>(transform.OutputSize().Width));
    profile.Video().Height(static_cast<uint32_t>(transform.OutputSize().Height));
    profile.Video().Bitrate((std::max)(4000000u, clip.GetVideoEncodingProperties().Bitrate()));
    MediaTranscoder transcoder; transcoder.AlwaysReencode(true);
    transcoder.TrimStartTime(clip.TrimTimeFromStart());
    transcoder.TrimStopTime(clip.OriginalDuration() - clip.TrimTimeFromEnd());
    transcoder.AddVideoEffect(transform.ActivatableClassId(), true, transform.Properties());
    const auto duration = clip.TrimmedDuration();
    auto preparation = transcoder.PrepareFileTranscodeAsync(input, output, profile).get();
    if (!preparation.CanTranscode()) throw hresult_error(E_FAIL, L"Cannot prepare video transform.");
    auto operation = preparation.TranscodeAsync();
    while (operation.Status() == AsyncStatus::Started) {
      if (cancelled->load()) operation.Cancel();
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    operation.get();
    clip = MediaClip::CreateFromFileAsync(output).get();
    if (clip.OriginalDuration() > duration) clip.TrimTimeFromEnd(clip.OriginalDuration() - duration);
  }
  return destination;
}

MediaClip NveImageClip(StorageFile const& file, int64_t duration, const flutter::EncodableMap& source,
    int canvas_width, int canvas_height) {
  auto stream = file.OpenAsync(FileAccessMode::Read).get();
  auto decoder = BitmapDecoder::CreateAsync(stream).get();
  auto pixels = decoder.GetPixelDataAsync(BitmapPixelFormat::Bgra8, BitmapAlphaMode::Premultiplied,
      BitmapTransform(), ExifOrientationMode::RespectExifOrientation, ColorManagementMode::ColorManageToSRgb).get().DetachPixelData();
  const int original_width = decoder.OrientedPixelWidth(), original_height = decoder.OrientedPixelHeight();
  int crop_width = original_width, crop_height = original_height;
  double target_width = canvas_width, target_height = canvas_height;
  if (GetValue(source, "rect")) {
    const auto& rect = NveMap(source, "rect");
    target_width *= GetDouble(rect, "width"); target_height *= GetDouble(rect, "height");
  }
  if (GetString(source, "fit") == "cover") {
    const auto aspect = target_width / target_height;
    if (original_width / static_cast<double>(original_height) > aspect) crop_width = (std::max)(1, static_cast<int>(original_height * aspect));
    else crop_height = (std::max)(1, static_cast<int>(original_width / aspect));
  }
  std::vector<uint8_t> adjusted(static_cast<size_t>(crop_width) * crop_height * 4);
  const bool flip_x = GetBool(source, "flipHorizontal"), flip_y = GetBool(source, "flipVertical");
  for (int y = 0; y < crop_height; ++y) for (int x = 0; x < crop_width; ++x) {
    const int source_x = (original_width - crop_width) / 2 + (flip_x ? crop_width - 1 - x : x);
    const int source_y = (original_height - crop_height) / 2 + (flip_y ? crop_height - 1 - y : y);
    std::memcpy(adjusted.data() + (static_cast<size_t>(y) * crop_width + x) * 4,
        pixels.data() + (static_cast<size_t>(source_y) * original_width + source_x) * 4, 4);
  }
  winrt::com_ptr<ID3D11Device> device;
  HRESULT result = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, nullptr);
  if (FAILED(result)) winrt::check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, nullptr));
  D3D11_TEXTURE2D_DESC description{};
  description.Width = crop_width; description.Height = crop_height;
  description.MipLevels = 1; description.ArraySize = 1;
  description.Format = DXGI_FORMAT_B8G8R8A8_UNORM; description.SampleDesc.Count = 1;
  description.Usage = D3D11_USAGE_DEFAULT;
  description.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
  D3D11_SUBRESOURCE_DATA data{}; data.pSysMem = adjusted.data(); data.SysMemPitch = description.Width * 4;
  winrt::com_ptr<ID3D11Texture2D> texture;
  winrt::check_hresult(device->CreateTexture2D(&description, &data, texture.put()));
  auto dxgi_surface = texture.as<IDXGISurface>();
  winrt::com_ptr<::IInspectable> inspectable;
  winrt::check_hresult(CreateDirect3D11SurfaceFromDXGISurface(dxgi_surface.get(), inspectable.put()));
  auto surface = inspectable.as<winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DSurface>();
  return MediaClip::CreateFromSurface(surface, std::chrono::milliseconds(duration));
}
}

void NativeVideoEditorPlugin::GetMediaInfo(const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto path = GetString(args, "inputPath");
  workers_.emplace_back([path, res = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result))]() {
    try {
      winrt::init_apartment();
      auto file = StorageFile::GetFileFromPathAsync(ToWString(path)).get();
      flutter::EncodableMap info;
      auto audio_info = [](uint32_t index, AudioEncodingProperties const& properties) {
        flutter::EncodableMap item;
        item[flutter::EncodableValue("index")] = flutter::EncodableValue(static_cast<int32_t>(index));
        item[flutter::EncodableValue("codec")] = flutter::EncodableValue(ToString(properties.Subtype()));
        item[flutter::EncodableValue("sampleRate")] = flutter::EncodableValue(static_cast<int32_t>(properties.SampleRate()));
        item[flutter::EncodableValue("channelCount")] = flutter::EncodableValue(static_cast<int32_t>(properties.ChannelCount()));
        item[flutter::EncodableValue("bitrate")] = flutter::EncodableValue(static_cast<int64_t>(properties.Bitrate()));
        return flutter::EncodableValue(item);
      };
      try {
        auto clip = MediaClip::CreateFromFileAsync(file).get();
        auto properties = clip.GetVideoEncodingProperties();
        auto metadata = file.Properties().GetVideoPropertiesAsync().get();
        info[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(NveMilliseconds(clip.OriginalDuration()));
        info[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int32_t>(properties.Width()));
        info[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<int32_t>(properties.Height()));
        info[flutter::EncodableValue("rotationDegrees")] = flutter::EncodableValue(static_cast<int32_t>(metadata.Orientation()));
        info[flutter::EncodableValue("hasAudio")] = flutter::EncodableValue(clip.EmbeddedAudioTracks().Size() > 0);
        if (clip.EmbeddedAudioTracks().Size() > 0) {
          info[flutter::EncodableValue("audioCodec")] = flutter::EncodableValue(ToString(clip.EmbeddedAudioTracks().GetAt(0).GetAudioEncodingProperties().Subtype()));
        }
        flutter::EncodableList audio_tracks;
        for (uint32_t index = 0; index < clip.EmbeddedAudioTracks().Size(); ++index) {
          audio_tracks.push_back(audio_info(index, clip.EmbeddedAudioTracks().GetAt(index).GetAudioEncodingProperties()));
        }
        info[flutter::EncodableValue("audioTracks")] = flutter::EncodableValue(audio_tracks);
        info[flutter::EncodableValue("videoCodec")] = flutter::EncodableValue(ToString(properties.Subtype()));
        info[flutter::EncodableValue("bitrate")] = flutter::EncodableValue(static_cast<int64_t>(properties.Bitrate()));
        if (properties.FrameRate().Denominator() > 0)
          info[flutter::EncodableValue("frameRate")] = flutter::EncodableValue(static_cast<double>(properties.FrameRate().Numerator()) / properties.FrameRate().Denominator());
      } catch (const hresult_error&) {
        auto audio = BackgroundAudioTrack::CreateFromFileAsync(file).get();
        info[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(NveMilliseconds(audio.OriginalDuration()));
        info[flutter::EncodableValue("width")] = flutter::EncodableValue(0);
        info[flutter::EncodableValue("height")] = flutter::EncodableValue(0);
        info[flutter::EncodableValue("hasAudio")] = flutter::EncodableValue(true);
        info[flutter::EncodableValue("audioCodec")] = flutter::EncodableValue(ToString(audio.GetAudioEncodingProperties().Subtype()));
        info[flutter::EncodableValue("audioTracks")] = flutter::EncodableValue(flutter::EncodableList{audio_info(0, audio.GetAudioEncodingProperties())});
      }
      res->Success(flutter::EncodableValue(info));
    } catch (const hresult_error& error) { res->Error("metadata_failed", ToString(error.message())); }
      catch (const std::exception& error) { res->Error("metadata_failed", error.what()); }
  });
}

void NativeVideoEditorPlugin::ComposeVideo(const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto output = GetString(args, "outputPath");
  auto cancelled = std::make_shared<std::atomic<bool>>(false);
  bool busy = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    busy = active_cancellations_.count(output) > 0;
    if (!busy) active_cancellations_[output] = cancelled;
  }
  if (busy) { result->Error("output_in_use", "Output already has an active export."); return; }
  workers_.emplace_back([this, args, output, cancelled,
      res = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result))]() {
    std::vector<std::filesystem::path> temporary;
    bool created_output = false;
    std::string stage = "Validating composition";
    bool succeeded = false;
    std::string failure;
    try {
      winrt::init_apartment();
      const auto clips = NveList(args, "clips"), overlays = NveList(args, "overlays"), tracks = NveList(args, "audioTracks");
      if (clips.empty()) throw hresult_invalid_argument(L"At least one clip is required.");
      for (const auto& list : {clips, overlays, tracks}) for (const auto& value : list) {
        const auto& source = std::get<flutter::EncodableMap>(value);
        const auto path = GetString(source, "path");
        if (!path.empty() && NveSamePath(path, output)) throw hresult_invalid_argument(L"Output must differ from every source.");
      }
      const auto& settings = NveMap(args, "settings");
      auto width = GetInt32(settings, "width"), height = GetInt32(settings, "height");
      const auto fps = GetInt32(settings, "frameRate");
      if (width == 0 && height == 0) {
        const auto& first = std::get<flutter::EncodableMap>(clips.front());
        auto file = StorageFile::GetFileFromPathAsync(ToWString(GetString(first, "path"))).get();
        auto properties = file.Properties().GetVideoPropertiesAsync().get();
        width = properties.Width(); height = properties.Height();
        if (static_cast<int>(properties.Orientation()) == 90 || static_cast<int>(properties.Orientation()) == 270) std::swap(width, height);
        width = width / 2 * 2; height = height / 2 * 2;
      }
      if (width < 2 || height < 2 || width > 8192 || height > 8192 || width % 2 || height % 2 || fps < 1 || fps > 120)
        throw hresult_invalid_argument(L"Invalid output size or frame rate.");
      auto check_cancel = [&]() { if (cancelled->load()) throw hresult_canceled(); };
      auto load = [&](const flutter::EncodableMap& source, bool image, int64_t duration) -> MediaClip {
        check_cancel();
        auto file = StorageFile::GetFileFromPathAsync(ToWString(GetString(source, "path"))).get();
        if (image) {
          if (duration <= 0) throw hresult_invalid_argument(L"Image clips need a duration.");
          return NveImageClip(file, duration, source, width, height);
        }
        return MediaClip::CreateFromFileAsync(file).get();
      };
      MediaComposition composition;
      MediaOverlayLayer main_layer;
      int64_t total = 0;
      for (const auto& value : clips) {
        const auto& source = std::get<flutter::EncodableMap>(value);
        const bool image = GetBool(source, "isImage");
        auto limit = GetInt64(source, "durationMs", INT64_MAX);
        const auto audio_cap = GetString(source, "capToAudio");
        if (!audio_cap.empty()) {
          auto audio_file = StorageFile::GetFileFromPathAsync(ToWString(audio_cap)).get();
          limit = (std::min)(limit, NveMilliseconds(BackgroundAudioTrack::CreateFromFileAsync(audio_file).get().OriginalDuration()));
        }
        stage = "Loading timeline clip";
        auto clip = load(source, image, limit);
        if (!image) NveTrim(clip, source, limit);
        const auto duration = NveMilliseconds(clip.TrimmedDuration());
        stage = "Fitting timeline clip";
        const auto position = NveFit(clip, source, Rect(0, 0, static_cast<float>(width), static_cast<float>(height)), temporary, cancelled);
        if (!image) clip.Volume(GetDouble(source, "volume", 1));
        MediaOverlay overlay(clip, position, 1.0);
        overlay.AudioEnabled(!image && GetDouble(source, "volume", 1) > 0);
        overlay.Delay(std::chrono::milliseconds(total));
        main_layer.Overlays().Append(overlay);
        total += duration;
      }
      composition.Clips().Append(MediaClip::CreateFromColor(winrt::Windows::UI::Color{255, 0, 0, 0}, std::chrono::milliseconds(total)));
      composition.OverlayLayers().Append(main_layer);
      for (const auto& value : overlays) {
        stage = "Loading overlay";
        auto source = std::get<flutter::EncodableMap>(value);
        const auto start = GetInt64(source, "startMs");
        if (start >= total) continue;
        const bool image = GetString(source, "type") != "video";
        const auto bytes = GetValue(source, "imageBytes");
        if (bytes && std::holds_alternative<std::vector<uint8_t>>(*bytes)) {
          GUID id; winrt::check_hresult(CoCreateGuid(&id));
          wchar_t name[64]; StringFromGUID2(id, name, 64);
          auto file = std::filesystem::temp_directory_path() / (std::wstring(L"nve-") + name + L".png");
          temporary.push_back(file);
          std::ofstream stream(file, std::ios::binary);
          const auto& data = std::get<std::vector<uint8_t>>(*bytes);
          stream.write(reinterpret_cast<const char*>(data.data()), data.size()); stream.close();
          if (!stream) throw hresult_error(E_FAIL, L"Cannot write caption image.");
          source[flutter::EncodableValue("path")] = flutter::EncodableValue(ToString(file.wstring()));
        }
        const auto duration = (std::min)(total - start, GetInt64(source, "durationMs", total - start));
        auto clip = load(source, image, duration);
        if (!image) NveTrim(clip, source, duration);
        const auto& rect = NveMap(source, "rect");
        Rect position(static_cast<float>(GetDouble(rect, "left") * width), static_cast<float>(GetDouble(rect, "top") * height),
          static_cast<float>(GetDouble(rect, "width") * width), static_cast<float>(GetDouble(rect, "height") * height));
        position = NveFit(clip, source, position, temporary, cancelled);
        MediaOverlay overlay(clip, position, GetDouble(source, "opacity", 1));
        overlay.AudioEnabled(false); overlay.Delay(std::chrono::milliseconds(start));
        MediaOverlayLayer layer; layer.Overlays().Append(overlay);
        composition.OverlayLayers().Append(layer);
      }
      for (const auto& value : tracks) {
        stage = "Loading background audio";
        const auto& source = std::get<flutter::EncodableMap>(value);
        auto at = GetInt64(source, "startMs");
        if (at >= total) continue;
        auto file = StorageFile::GetFileFromPathAsync(ToWString(GetString(source, "path"))).get();
        auto track = BackgroundAudioTrack::CreateFromFileAsync(file).get();
        const auto original = NveMilliseconds(track.OriginalDuration()), segment = NveSegment(source, original);
        do {
          check_cancel();
          auto copy = track.Clone();
          const auto duration = (std::min)(segment, total - at);
          const auto trim_start = GetInt64(source, "trimStartMs");
          copy.TrimTimeFromStart(std::chrono::milliseconds(trim_start));
          copy.TrimTimeFromEnd(std::chrono::milliseconds(original - trim_start - duration));
          copy.Delay(std::chrono::milliseconds(at)); copy.Volume(GetDouble(source, "volume", 1));
          composition.BackgroundAudioTracks().Append(copy);
          at += duration;
        } while (GetBool(source, "loop") && at < total);
      }
      check_cancel();
      stage = "Rendering composition";
      auto file = CreateOrReplaceOutputFile(output); created_output = true;
      auto profile = MediaEncodingProfile::CreateMp4(VideoEncodingQuality::HD720p);
      profile.Video().Width(width); profile.Video().Height(height);
      profile.Video().FrameRate().Numerator(fps); profile.Video().FrameRate().Denominator(1);
      profile.Video().Bitrate(GetInt32(settings, "videoBitrate", 4000000));
      profile.Audio().Bitrate(GetInt32(settings, "audioBitrate", 128000));
      auto operation = composition.RenderToFileAsync(file, MediaTrimmingPreference::Precise, profile);
      operation.Progress([this, output](auto const&, double progress) { ReportProgress(output, progress / 100.0); });
      while (operation.Status() == AsyncStatus::Started) {
        if (cancelled->load()) operation.Cancel();
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
      }
      const auto reason = operation.get();
      check_cancel();
      if (reason != TranscodeFailureReason::None) throw hresult_error(E_FAIL, L"Windows could not encode this composition with the requested settings.");
      ReportProgress(output, 1.0);
      succeeded = true;
    } catch (const hresult_error& error) {
      if (created_output) { std::error_code ignored; std::filesystem::remove(ToWString(output), ignored); }
      failure = stage + ": " + ToString(error.message());
    } catch (const std::exception& error) {
      if (created_output) { std::error_code ignored; std::filesystem::remove(ToWString(output), ignored); }
      failure = stage + ": " + error.what();
    }
    for (const auto& file : temporary) { std::error_code ignored; std::filesystem::remove(file, ignored); }
    { std::lock_guard<std::mutex> lock(mutex_); active_cancellations_.erase(output); }
    if (succeeded) res->Success(flutter::EncodableValue(output));
    else res->Error("composition_failed", failure);
  });
}

}  // namespace native_video_editor
