#include "native_video_editor_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Editing.h>
#include <winrt/Windows.Media.Transcoding.h>
#include <winrt/Windows.Media.MediaProperties.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Graphics.Imaging.h>

#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <chrono>

using namespace winrt;
using namespace Windows::Foundation;
using namespace Windows::Media::Editing;
using namespace Windows::Media::MediaProperties;
using namespace Windows::Media::Transcoding;
using namespace Windows::Storage;
using namespace Windows::Storage::Streams;
using namespace Windows::Graphics::Imaging;

namespace native_video_editor {

namespace {

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
  winrt::init_apartment();
}

NativeVideoEditorPlugin::~NativeVideoEditorPlugin() {}

void NativeVideoEditorPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("invalid_arguments", "Expected argument map.");
    return;
  }

  if (method_call.method_name() == "processVideo") {
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

  auto cancelled = std::make_shared<std::atomic<bool>>(false);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    active_cancellations_[output_path] = cancelled;
  }

  std::thread([this, input_path, output_path, trim_start_ms, trim_end_ms, target_width, target_height, rotation_degrees, speed_multiplier, mute_audio, cancelled, res = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result))]() mutable {
    try {
      StorageFile input_file = StorageFile::GetFileFromPathAsync(ToWString(input_path)).get();
      MediaClip clip = MediaClip::CreateFromFileAsync(input_file).get();

      if (trim_start_ms >= 0) {
        clip.TrimStartTime(std::chrono::milliseconds(trim_start_ms));
      }
      if (trim_end_ms >= 0) {
        clip.TrimEndTime(std::chrono::milliseconds(trim_end_ms));
      }
      if (mute_audio) {
        clip.Volume(0.0);
      }

      MediaComposition comp;
      comp.Clips().Append(clip);

      // Create output file parent directory if needed
      std::wstring w_output = ToWString(output_path);
      size_t last_slash = w_output.find_last_of(L"\\/");
      if (last_slash != std::wstring::npos) {
        std::wstring dir_path = w_output.substr(0, last_slash);
        StorageFolder::GetFolderFromPathAsync(dir_path).get();
      }

      StorageFile output_file = StorageFile::CreateStreamedFileFromUriAsync(ToWString(output_path), Uri(ToWString(output_path)), nullptr).get();
      MediaEncodingProfile profile = MediaEncodingProfile::CreateMp4(VideoEncodingQuality::HD1080p);

      if (target_width > 0 && target_height > 0) {
        profile.Video().Width(target_width);
        profile.Video().Height(target_height);
      }

      auto async_op = comp.RenderToFileAsync(output_file, MediaVideoProcessingMode::Buffer, profile);
      async_op.Progress([this, output_path](auto const& asyncInfo, double progress) {
        if (channel_) {
          flutter::EncodableMap args;
          args[flutter::EncodableValue("outputPath")] = flutter::EncodableValue(output_path);
          args[flutter::EncodableValue("progress")] = flutter::EncodableValue(progress / 100.0);
          channel_->InvokeMethod("onProgress", std::make_unique<flutter::EncodableValue>(args));
        }
      });

      async_op.get();

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
      res->Error("processing_failed", ToString(ex.message()));
    } catch (...) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        active_cancellations_.erase(output_path);
      }
      res->Error("processing_failed", "An error occurred during video processing.");
    }
  }).detach();
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

  std::thread([input_path, output_path, position_ms, quality, res = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result))]() mutable {
    try {
      StorageFile input_file = StorageFile::GetFileFromPathAsync(ToWString(input_path)).get();
      MediaClip clip = MediaClip::CreateFromFileAsync(input_file).get();
      MediaComposition comp;
      comp.Clips().Append(clip);

      ImageStream stream = comp.GetThumbnailAsync(
          std::chrono::milliseconds(position_ms),
          0, 0,
          VideoFramePrecision::NearestFrame).get();

      StorageFile output_file = StorageFile::CreateStreamedFileFromUriAsync(ToWString(output_path), Uri(ToWString(output_path)), nullptr).get();
      IRandomAccessStream output_stream = output_file.OpenAsync(FileAccessMode::ReadWrite).get();

      BitmapDecoder decoder = BitmapDecoder::CreateAsync(stream).get();
      SoftwareBitmap bitmap = decoder.GetSoftwareBitmapAsync().get();

      Guid encoder_id = BitmapEncoder::JpegEncoderId();
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
      res->Error("thumbnail_failed", ToString(ex.message()));
    } catch (...) {
      res->Error("thumbnail_failed", "An error occurred during thumbnail extraction.");
    }
  }).detach();
}

void NativeVideoEditorPlugin::ComposeImageWithAudio(
    const flutter::EncodableMap &args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::string image_path = GetString(args, "imagePath");
  std::string audio_path = GetString(args, "audioPath");
  std::string output_path = GetString(args, "outputPath");
  int64_t audio_duration_ms = GetInt64(args, "audioDurationMs", 5000);

  std::thread([image_path, audio_path, output_path, audio_duration_ms, res = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result))]() mutable {
    try {
      StorageFile image_file = StorageFile::GetFileFromPathAsync(ToWString(image_path)).get();
      StorageFile audio_file = StorageFile::GetFileFromPathAsync(ToWString(audio_path)).get();

      MediaClip image_clip = MediaClip::CreateFromImageFileAsync(image_file, std::chrono::milliseconds(audio_duration_ms)).get();
      BackgroundAudioTrack audio_track = BackgroundAudioTrack::CreateFromFileAsync(audio_file).get();

      MediaComposition comp;
      comp.Clips().Append(image_clip);
      comp.BackgroundAudioTracks().Append(audio_track);

      StorageFile output_file = StorageFile::CreateStreamedFileFromUriAsync(ToWString(output_path), Uri(ToWString(output_path)), nullptr).get();
      MediaEncodingProfile profile = MediaEncodingProfile::CreateMp4(VideoEncodingQuality::HD1080p);

      comp.RenderToFileAsync(output_file, MediaVideoProcessingMode::Buffer, profile).get();
      res->Success(flutter::EncodableValue(output_path));
    } catch (const hresult_error& ex) {
      res->Error("compose_failed", ToString(ex.message()));
    } catch (...) {
      res->Error("compose_failed", "An error occurred during image video composition.");
    }
  }).detach();
}

void NativeVideoEditorPlugin::MergeAudioIntoVideo(
    const flutter::EncodableMap &args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::string input_video_path = GetString(args, "inputVideoPath");
  std::string audio_path = GetString(args, "audioPath");
  std::string output_path = GetString(args, "outputPath");
  bool replace_existing_audio = GetBool(args, "replaceExistingAudio", true);

  std::thread([input_video_path, audio_path, output_path, replace_existing_audio, res = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result))]() mutable {
    try {
      StorageFile video_file = StorageFile::GetFileFromPathAsync(ToWString(input_video_path)).get();
      StorageFile audio_file = StorageFile::GetFileFromPathAsync(ToWString(audio_path)).get();

      MediaClip video_clip = MediaClip::CreateFromFileAsync(video_file).get();
      if (replace_existing_audio) {
        video_clip.Volume(0.0);
      }

      BackgroundAudioTrack audio_track = BackgroundAudioTrack::CreateFromFileAsync(audio_file).get();

      MediaComposition comp;
      comp.Clips().Append(video_clip);
      comp.BackgroundAudioTracks().Append(audio_track);

      StorageFile output_file = StorageFile::CreateStreamedFileFromUriAsync(ToWString(output_path), Uri(ToWString(output_path)), nullptr).get();
      MediaEncodingProfile profile = MediaEncodingProfile::CreateMp4(VideoEncodingQuality::HD1080p);

      comp.RenderToFileAsync(output_file, MediaVideoProcessingMode::Buffer, profile).get();
      res->Success(flutter::EncodableValue(output_path));
    } catch (const hresult_error& ex) {
      res->Error("merge_failed", ToString(ex.message()));
    } catch (...) {
      res->Error("merge_failed", "An error occurred during audio merge.");
    }
  }).detach();
}

}  // namespace native_video_editor
