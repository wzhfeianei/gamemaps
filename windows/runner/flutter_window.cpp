#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>

#include <windows.h>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>

// Helper function to convert wstring to string
std::string WStringToString(const std::wstring& wstr) {
  if (wstr.empty()) return std::string();
  int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, NULL, 0, NULL, NULL);
  std::string str(size_needed, 0);
  WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &str[0], size_needed, NULL, NULL);
  return str;
}

// Helper function to capture window screenshot
std::vector<uint8_t> CaptureWindowImage(HWND hwnd) {
  std::vector<uint8_t> image_data;
  
  // Get window dimensions
  RECT rect;
  if (!GetWindowRect(hwnd, &rect)) {
    return image_data;
  }
  
  int width = rect.right - rect.left;
  int height = rect.bottom - rect.top;
  
  if (width <= 0 || height <= 0) {
    return image_data;
  }
  
  // Create device contexts
  HDC hdcScreen = GetDC(NULL);
  HDC hdcMem = CreateCompatibleDC(hdcScreen);
  
  // Create bitmap
  HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, width, height);
  HBITMAP hOldBitmap = (HBITMAP)SelectObject(hdcMem, hBitmap);
  
  // Capture the window
  BitBlt(hdcMem, 0, 0, width, height, hdcScreen, rect.left, rect.top, SRCCOPY);
  
  // Get bitmap info
  BITMAPINFOHEADER bi;
  ZeroMemory(&bi, sizeof(BITMAPINFOHEADER));
  bi.biSize = sizeof(BITMAPINFOHEADER);
  bi.biWidth = width;
  bi.biHeight = -height; // Negative for top-down bitmap
  bi.biPlanes = 1;
  bi.biBitCount = 32;
  bi.biCompression = BI_RGB;
  
  // Calculate image size
  DWORD imageSize = ((width * bi.biBitCount + 31) / 32) * 4 * height;
  
  // Create buffer for bitmap data
  std::vector<uint8_t> bitmapData(imageSize);
  
  // Get bitmap bits
  GetDIBits(hdcMem, hBitmap, 0, height, bitmapData.data(), (BITMAPINFO*)&bi, DIB_RGB_COLORS);
  
  // Create a simple BMP file header and write it to the result
  // BMP file header
  BITMAPFILEHEADER bmfh;
  bmfh.bfType = 0x4D42; // BM
  bmfh.bfSize = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER) + imageSize;
  bmfh.bfReserved1 = 0;
  bmfh.bfReserved2 = 0;
  bmfh.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
  
  // Write BMP file header
  image_data.insert(image_data.end(), (uint8_t*)&bmfh, (uint8_t*)&bmfh + sizeof(BITMAPFILEHEADER));
  
  // Write BMP info header
  image_data.insert(image_data.end(), (uint8_t*)&bi, (uint8_t*)&bi + sizeof(BITMAPINFOHEADER));
  
  // Write bitmap data
  image_data.insert(image_data.end(), bitmapData.begin(), bitmapData.end());
  
  // Cleanup
  SelectObject(hdcMem, hOldBitmap);
  DeleteObject(hBitmap);
  DeleteDC(hdcMem);
  ReleaseDC(NULL, hdcScreen);
  
  return image_data;
}

// Window enumeration callback data
struct WindowEnumData {
  std::vector<std::string>* window_titles;
  HWND target_hwnd;
  const std::string* target_title;
};

// Window enumeration callback function
BOOL CALLBACK EnumWindowsProc(HWND hwnd, LPARAM lparam) {
  WindowEnumData* data = reinterpret_cast<WindowEnumData*>(lparam);
  
  // Skip invisible windows
  if (!IsWindowVisible(hwnd)) {
    return TRUE;
  }
  
  // Skip windows without title
  wchar_t title[1024] = L"";
  GetWindowTextW(hwnd, title, sizeof(title) / sizeof(wchar_t));
  if (title[0] == L'\0') {
    return TRUE;
  }
  
  std::string title_utf8 = WStringToString(title);
  
  // If we're looking for a specific window
  if (data->target_title != nullptr) {
    if (title_utf8 == *data->target_title) {
      data->target_hwnd = hwnd;
      return FALSE; // Stop enumeration
    }
  }
  
  // Otherwise, add to the list
  if (data->window_titles != nullptr) {
    data->window_titles->push_back(title_utf8);
  }
  
  return TRUE;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Create method channel for screen capture
  screen_capture_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.gamemaps/screen_capture",
      &flutter::StandardMethodCodec::GetInstance());
  
  // Set method call handler
  screen_capture_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  screen_capture_channel_ = nullptr;
  
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result = flutter_controller_->HandleTopLevelWindowProc(
        hwnd, message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();
  
  if (method == "captureScreen") {
    // Capture the entire screen by getting the desktop window
    HWND desktop_hwnd = GetDesktopWindow();
    std::vector<uint8_t> image_data = CaptureWindowImage(desktop_hwnd);
    result->Success(flutter::EncodableValue(image_data));
  } else if (method == "captureWindow") {
    // Get window name from arguments
    const flutter::EncodableMap* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("invalid_arguments", "No arguments provided");
      return;
    }
    
    auto window_name_it = arguments->find(flutter::EncodableValue("windowName"));
    if (window_name_it == arguments->end()) {
      result->Error("invalid_arguments", "windowName is required");
      return;
    }
    
    const std::string* window_name = std::get_if<std::string>(&window_name_it->second);
    if (!window_name) {
      result->Error("invalid_arguments", "windowName must be a string");
      return;
    }
    
    // Find the window with the specified name
    WindowEnumData data;
    data.window_titles = nullptr;
    data.target_hwnd = nullptr;
    data.target_title = window_name;
    
    EnumWindows(EnumWindowsProc, reinterpret_cast<LPARAM>(&data));
    
    if (data.target_hwnd != nullptr) {
      // Capture the window
      std::vector<uint8_t> image_data = CaptureWindowImage(data.target_hwnd);
      result->Success(flutter::EncodableValue(image_data));
    } else {
      result->Error("window_not_found", "Window not found");
    }
  } else if (method == "getRunningWindows") {
    // Get all running windows with visible titles
    std::vector<std::string> window_titles;
    
    WindowEnumData data;
    data.window_titles = &window_titles;
    data.target_hwnd = nullptr;
    data.target_title = nullptr;
    
    EnumWindows(EnumWindowsProc, reinterpret_cast<LPARAM>(&data));
    
    // Convert to EncodableList
    flutter::EncodableList result_list;
    for (const auto& title : window_titles) {
      result_list.push_back(flutter::EncodableValue(title));
    }
    
    result->Success(flutter::EncodableValue(result_list));
  } else {
    result->NotImplemented();
  }
}
