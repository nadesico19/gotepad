#include "ios_model_file_picker.hpp"
#include <godot_cpp/core/class_db.hpp>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#include <mutex>
#include <string>

struct IOSModelPickerState {
  std::mutex mutex;
  bool pending = false;
  bool ready = false;
  bool cancelled = false;
  std::string path;
  std::string error;
  __weak UIDocumentPickerViewController* picker = nil;
};

@interface GotepadModelPickerDelegate : NSObject <UIDocumentPickerDelegate> {
@public
  std::shared_ptr<IOSModelPickerState> state_;
}
@end

@implementation GotepadModelPickerDelegate
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller {
  std::lock_guard<std::mutex> lock(state_->mutex);
  state_->pending = false;
  state_->cancelled = true;
  state_->ready = true;
}
- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
  auto state = state_;
  NSURL* url = urls.firstObject;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    @autoreleasepool {
      BOOL scoped = [url startAccessingSecurityScopedResource];
      NSError* error = nil;
      NSNumber* size = nil;
      [url getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
      NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
      NSString* directory = [documents stringByAppendingPathComponent:@".tmp/model-import"];
      NSString* filename = [NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, url.lastPathComponent];
      NSURL* target = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:filename]];
      bool copied = false;
      if (url != nil && error == nil && size.unsignedLongLongValue >= 1024 && size.unsignedLongLongValue <= 1024ULL*1024*1024) {
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
        if (error == nil)
          copied = [[NSFileManager defaultManager] copyItemAtURL:url toURL:target error:&error];
      }
      if (scoped) [url stopAccessingSecurityScopedResource];
      std::lock_guard<std::mutex> lock(state->mutex);
      if (!state->pending) {
        if (copied) [[NSFileManager defaultManager] removeItemAtURL:target error:nil];
        return;
      }
      state->pending = false;
      state->ready = true;
      if (copied) state->path = target.path.UTF8String;
      else state->error = error != nil ? error.localizedDescription.UTF8String : "模型文件大小必须在 1 KB 到 1 GB 之间。";
    }
  });
}
@end

void IOSModelFilePicker::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("open_file"), &IOSModelFilePicker::open_file);
  godot::ClassDB::bind_method(godot::D_METHOD("cancel"), &IOSModelFilePicker::cancel);
  godot::ClassDB::bind_method(godot::D_METHOD("poll_result"), &IOSModelFilePicker::poll_result);
}

IOSModelFilePicker::IOSModelFilePicker() : state_(std::make_shared<IOSModelPickerState>()) {}

bool IOSModelFilePicker::open_file() {
  auto state = state_;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->pending) return false;
    state->pending = true;
    state->ready = state->cancelled = false;
    state->path.clear();
    state->error.clear();
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->pending) return;
    UIViewController* presenter = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
      if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
      for (UIWindow* window in ((UIWindowScene*)scene).windows) {
        if (window.isKeyWindow) { presenter = window.rootViewController; break; }
      }
      if (presenter != nil) break;
    }
    while (presenter.presentedViewController != nil) presenter = presenter.presentedViewController;
    if (presenter == nil) {
      state->error = "无法打开 iOS 文件选择器。";
      state->pending = false;
      state->ready = true;
      return;
    }
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:NO];
    picker.allowsMultipleSelection = NO;
    GotepadModelPickerDelegate* delegate = [GotepadModelPickerDelegate new];
    delegate->state_ = state;
    picker.delegate = delegate;
    objc_setAssociatedObject(picker, @selector(open_file), delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    state->picker = picker;
    [presenter presentViewController:picker animated:YES completion:nil];
  });
  return true;
}

void IOSModelFilePicker::cancel() {
  auto state = state_;
  dispatch_async(dispatch_get_main_queue(), ^{
    std::lock_guard<std::mutex> lock(state->mutex);
    state->pending = false;
    state->ready = false;
    if (!state->path.empty()) {
      [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithUTF8String:state->path.c_str()] error:nil];
      state->path.clear();
    }
    [state->picker dismissViewControllerAnimated:YES completion:nil];
  });
}

godot::Dictionary IOSModelFilePicker::poll_result() {
  std::lock_guard<std::mutex> lock(state_->mutex);
  godot::Dictionary result;
  if (!state_->ready) return result;
  result["path"] = godot::String::utf8(state_->path.c_str());
  result["error"] = godot::String::utf8(state_->error.c_str());
  result["cancelled"] = state_->cancelled;
  state_->ready = false;
  state_->path.clear();
  return result;
}
