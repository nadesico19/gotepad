#include "ios_sgf_file_bridge.hpp"
#include "ios_sgf_import.hpp"
#include <godot_cpp/core/class_db.hpp>
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#include <mutex>
#include <string>

struct IOSSGFResult {
  std::string path;
  std::string source_path;
  std::string error;
  bool cancelled = false;
  std::string bookmark;
};

struct IOSSGFPickerState {
  std::mutex mutex;
  bool pending = false;
  bool ready = false;
  bool image = false;
  bool exporting = false;
  IOSSGFResult result;
  __weak UIViewController* picker = nil;
};

namespace {
IOSSGFResult import_sgf_(NSURL* url) {
  NSDictionary* imported = import_ios_sgf(url);
  IOSSGFResult result;
  result.path = [imported[@"path"] UTF8String];
  result.source_path = [(imported[@"source_path"] ?: @"") UTF8String];
  result.error = [imported[@"error"] UTF8String];
  return result;
}

IOSSGFResult store_image_(UIImage* image, NSString* filename) {
  IOSSGFResult result;
  if (image == nil) { result.error = "无法读取所选图片。"; return result; }
  // Normalize orientation and HEIC to PNG, which Godot can decode.
  CGFloat scale = MIN(1.0, 2400.0 / MAX(image.size.width, image.size.height));
  CGSize size = CGSizeMake(MAX(1, image.size.width * scale), MAX(1, image.size.height * scale));
  UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat defaultFormat];
  format.scale = 1;
  UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
  NSData* png = [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext* context) {
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
  }];
  NSError* error = nil;
  NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  NSString* directory = [[documents stringByAppendingPathComponent:@".tmp/image-import"] stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSString* path = [directory stringByAppendingPathComponent:[filename.stringByDeletingPathExtension stringByAppendingPathExtension:@"png"]];
  if ([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error] && [png writeToFile:path options:NSDataWritingAtomic error:&error]) result.path = path.UTF8String;
  else result.error = error != nil ? error.localizedDescription.UTF8String : "无法导入图片。";
  return result;
}
IOSSGFResult import_image_(NSURL* url) {
  IOSSGFResult result;
  if (url == nil || !url.isFileURL) {
    result.error = "无法读取所选图片。";
    return result;
  }
  BOOL scoped = [url startAccessingSecurityScopedResource];
  NSError* error = nil;
  __block NSData* data = nil;
  NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
  [coordinator coordinateReadingItemAtURL:url options:0 error:&error byAccessor:^(NSURL* source) {
    data = [NSData dataWithContentsOfURL:source];
  }];
  if (scoped) [url stopAccessingSecurityScopedResource];
  UIImage* image = data != nil ? [UIImage imageWithData:data] : nil;
  if (image == nil) {
    result.error = error != nil ? error.localizedDescription.UTF8String : "无法读取所选图片。";
    return result;
  }
  return store_image_(image, url.lastPathComponent);
}

IOSSGFResult exported_result_(NSURL* url) {
  IOSSGFResult result;
  if (url == nil) { result.error = "系统未返回保存位置。"; return result; }
  result.path = url.path.UTF8String;
  result.source_path = ios_sgf_source_path(url).UTF8String;
  BOOL scoped = [url startAccessingSecurityScopedResource];
  NSData* bookmark = [url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
  if (bookmark != nil) result.bookmark = [bookmark base64EncodedStringWithOptions:0].UTF8String;
  if (scoped) [url stopAccessingSecurityScopedResource];
  return result;
}

godot::Dictionary result_dictionary_(const IOSSGFResult& value) {
  godot::Dictionary result;
  result["path"] = godot::String::utf8(value.path.c_str());
  result["source_path"] = godot::String::utf8(value.source_path.c_str());
  result["error"] = godot::String::utf8(value.error.c_str());
  result["cancelled"] = value.cancelled;
  result["bookmark"] = godot::String::utf8(value.bookmark.c_str());
  return result;
}
}

@interface GotepadSGFPickerDelegate : NSObject <UIDocumentPickerDelegate> {
@public
  std::shared_ptr<IOSSGFPickerState> state_;
}
@end

@implementation GotepadSGFPickerDelegate
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller {
  std::lock_guard<std::mutex> lock(state_->mutex);
  if (!state_->pending) return;
  state_->pending = false;
  state_->result.cancelled = true;
  state_->ready = true;
}
- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
  auto state = state_;
  NSURL* url = urls.firstObject;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    @autoreleasepool {
      auto result = state->exporting ? exported_result_(url) : (state->image ? import_image_(url) : import_sgf_(url));
      std::lock_guard<std::mutex> lock(state->mutex);
      if (!state->pending) return;
      state->result = std::move(result);
      state->pending = false;
      state->ready = true;
    }
  });
}
@end

@interface GotepadPhotoPickerDelegate : NSObject <PHPickerViewControllerDelegate> {
@public
  std::shared_ptr<IOSSGFPickerState> state_;
}
@end

@implementation GotepadPhotoPickerDelegate
- (void)picker:(PHPickerViewController*)picker didFinishPicking:(NSArray<PHPickerResult*>*)results {
  auto state = state_;
  [picker dismissViewControllerAnimated:YES completion:nil];
  if (results.count == 0) {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->pending) return;
    state->pending = false;
    state->result.cancelled = true;
    state->ready = true;
    return;
  }
  NSItemProvider* provider = results.firstObject.itemProvider;
  // The provider URL is temporary: import it inside this callback before it expires.
  [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSURL* url, NSError* error) {
    @autoreleasepool {
      IOSSGFResult result;
      if (url != nil) result = import_image_(url);
      else result.error = error != nil ? error.localizedDescription.UTF8String : "无法读取所选照片。";
      std::lock_guard<std::mutex> lock(state->mutex);
      if (!state->pending) return;
      state->result = std::move(result);
      state->pending = false;
      state->ready = true;
    }
  }];
}
@end

namespace {
void present_image_source_(std::shared_ptr<IOSSGFPickerState> state, UIViewController* presenter, bool photos) {
  std::lock_guard<std::mutex> lock(state->mutex);
  if (!state->pending) return;
  UIViewController* controller = nil;
  if (photos) {
    PHPickerConfiguration* configuration = [PHPickerConfiguration new];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController* picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    GotepadPhotoPickerDelegate* delegate = [GotepadPhotoPickerDelegate new];
    delegate->state_ = state;
    picker.delegate = delegate;
    objc_setAssociatedObject(picker, @selector(open_image), delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    controller = picker;
  } else {
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.allowsMultipleSelection = NO;
    GotepadSGFPickerDelegate* delegate = [GotepadSGFPickerDelegate new];
    delegate->state_ = state;
    picker.delegate = delegate;
    objc_setAssociatedObject(picker, @selector(open_image), delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    controller = picker;
  }
  state->picker = controller;
  [presenter presentViewController:controller animated:YES completion:nil];
}
}

@interface GotepadCameraDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate> {
@public
  std::shared_ptr<IOSSGFPickerState> state_;
}
@end

@implementation GotepadCameraDelegate
- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker {
  [picker dismissViewControllerAnimated:YES completion:nil];
  std::lock_guard<std::mutex> lock(state_->mutex);
  if (!state_->pending) return;
  state_->pending = false;
  state_->result.cancelled = true;
  state_->ready = true;
}
- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id>*)info {
  UIImage* image = info[UIImagePickerControllerOriginalImage];
  auto state = state_;
  [picker dismissViewControllerAnimated:YES completion:nil];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    @autoreleasepool {
      auto result = store_image_(image, @"camera.png");
      std::lock_guard<std::mutex> lock(state->mutex);
      if (!state->pending) return;
      state->result = std::move(result);
      state->pending = false;
      state->ready = true;
    }
  });
}
@end

@interface NSObject (GotepadSGFReceiverPolling)
+ (NSArray<NSDictionary*>*)drain_results;
@end

void IOSSGFFileBridge::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("open_file"), &IOSSGFFileBridge::open_file);
  godot::ClassDB::bind_method(godot::D_METHOD("open_image"), &IOSSGFFileBridge::open_image);
  godot::ClassDB::bind_method(godot::D_METHOD("open_camera"), &IOSSGFFileBridge::open_camera);
  godot::ClassDB::bind_method(godot::D_METHOD("open_image_source", "title", "album_label", "file_label", "cancel_label"), &IOSSGFFileBridge::open_image_source);
  godot::ClassDB::bind_method(godot::D_METHOD("export_file", "path"), &IOSSGFFileBridge::export_file);
  godot::ClassDB::bind_method(godot::D_METHOD("overwrite_file", "path", "bookmark"), &IOSSGFFileBridge::overwrite_file);
  godot::ClassDB::bind_method(godot::D_METHOD("cancel"), &IOSSGFFileBridge::cancel);
  godot::ClassDB::bind_method(godot::D_METHOD("poll_result"), &IOSSGFFileBridge::poll_result);
  godot::ClassDB::bind_method(godot::D_METHOD("poll_external_files"), &IOSSGFFileBridge::poll_external_files);
}

IOSSGFFileBridge::IOSSGFFileBridge() : state_(std::make_shared<IOSSGFPickerState>()) {}

bool IOSSGFFileBridge::open_file() { return open_picker_(false, {}); }

bool IOSSGFFileBridge::open_image() { return open_picker_(true, {}); }

bool IOSSGFFileBridge::open_camera() {
  auto state = state_;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->pending) return false;
    state->pending = true;
    state->ready = false;
    state->result = {};
    state->image = true;
    state->exporting = false;
  }
  auto present = ^(BOOL granted) {
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
      if (!granted || presenter == nil || ![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        state->result.error = !granted ? "无法使用相机，请在系统设置中允许 Gotepad 访问相机。" : "当前设备无法使用相机。";
        state->pending = false;
        state->ready = true;
        return;
      }
      UIImagePickerController* picker = [UIImagePickerController new];
      picker.sourceType = UIImagePickerControllerSourceTypeCamera;
      picker.mediaTypes = @[UTTypeImage.identifier];
      picker.cameraCaptureMode = UIImagePickerControllerCameraCaptureModePhoto;
      picker.allowsEditing = NO;
      picker.modalPresentationStyle = UIModalPresentationFullScreen;
      GotepadCameraDelegate* delegate = [GotepadCameraDelegate new];
      delegate->state_ = state;
      picker.delegate = delegate;
      objc_setAssociatedObject(picker, @selector(open_camera), delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      state->picker = picker;
      [presenter presentViewController:picker animated:YES completion:nil];
    });
  };
  AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (status == AVAuthorizationStatusNotDetermined)
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:present];
  else present(status == AVAuthorizationStatusAuthorized);
  return true;
}

bool IOSSGFFileBridge::open_image_source(const godot::String& title, const godot::String& album_label, const godot::String& file_label, const godot::String& cancel_label) {
  auto state = state_;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->pending) return false;
    state->pending = true;
    state->ready = false;
    state->result = {};
    state->image = true;
    state->exporting = false;
  }
  NSString* dialog_title = [NSString stringWithUTF8String:title.utf8().get_data()];
  NSString* album = [NSString stringWithUTF8String:album_label.utf8().get_data()];
  NSString* files = [NSString stringWithUTF8String:file_label.utf8().get_data()];
  NSString* cancel = [NSString stringWithUTF8String:cancel_label.utf8().get_data()];
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
      state->result.error = "无法打开 iOS 图片选择器。";
      state->pending = false;
      state->ready = true;
      return;
    }
    UIAlertController* chooser = [UIAlertController alertControllerWithTitle:dialog_title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [chooser addAction:[UIAlertAction actionWithTitle:album style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
      [presenter dismissViewControllerAnimated:YES completion:^{ present_image_source_(state, presenter, true); }];
    }]];
    [chooser addAction:[UIAlertAction actionWithTitle:files style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
      [presenter dismissViewControllerAnimated:YES completion:^{ present_image_source_(state, presenter, false); }];
    }]];
    [chooser addAction:[UIAlertAction actionWithTitle:cancel style:UIAlertActionStyleCancel handler:^(UIAlertAction* action) {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (!state->pending) return;
      state->pending = false;
      state->result.cancelled = true;
      state->ready = true;
    }]];
    state->picker = chooser;
    [presenter presentViewController:chooser animated:YES completion:nil];
  });
  return true;
}

bool IOSSGFFileBridge::export_file(const godot::String& path) { return open_picker_(false, path); }

bool IOSSGFFileBridge::open_picker_(bool image, const godot::String& export_path) {
  auto state = state_;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->pending) return false;
    state->pending = true;
    state->ready = false;
    state->result = {};
    state->image = image;
    state->exporting = !export_path.is_empty();
  }
  NSString* source_path = [NSString stringWithUTF8String:export_path.utf8().get_data()];
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
      state->result.error = "无法打开 iOS 文件选择器。";
      state->pending = false;
      state->ready = true;
      return;
    }
    UTType* sgf = [UTType typeWithFilenameExtension:@"sgf"];
    UIDocumentPickerViewController* picker = nil;
    if (state->exporting) {
      if (![[NSFileManager defaultManager] fileExistsAtPath:source_path]) {
        state->result.error = "无法读取待保存的文件。";
        state->pending = false;
        state->ready = true;
        return;
      }
      picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[[NSURL fileURLWithPath:source_path]] asCopy:YES];
    } else {
      // SGF imports make their own private copy after retaining the original identity.
      picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[state->image ? UTTypeImage : (sgf ?: UTTypeData)] asCopy:state->image];
    }
    picker.allowsMultipleSelection = NO;
    GotepadSGFPickerDelegate* delegate = [GotepadSGFPickerDelegate new];
    delegate->state_ = state;
    picker.delegate = delegate;
    objc_setAssociatedObject(picker, @selector(open_file), delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    state->picker = picker;
    [presenter presentViewController:picker animated:YES completion:nil];
  });
  return true;
}

bool IOSSGFFileBridge::overwrite_file(const godot::String& path, const godot::String& bookmark) {
  auto state = state_;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->pending) return false;
    state->pending = true;
    state->ready = false;
    state->result = {};
  }
  NSString* source_path = [NSString stringWithUTF8String:path.utf8().get_data()];
  NSString* encoded = [NSString stringWithUTF8String:bookmark.utf8().get_data()];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    @autoreleasepool {
      NSError* error = nil;
      BOOL stale = NO;
      NSData* bookmark_data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
      NSURL* target = bookmark_data != nil ? [NSURL URLByResolvingBookmarkData:bookmark_data options:NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:&error] : nil;
      IOSSGFResult result;
      if (target != nil) {
        BOOL scoped = [target startAccessingSecurityScopedResource];
        NSData* data = [NSData dataWithContentsOfFile:source_path options:0 error:&error];
        if (data != nil) {
          NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
          __block NSError* write_error = nil;
          __block BOOL written = NO;
          [coordinator coordinateWritingItemAtURL:target options:NSFileCoordinatorWritingForReplacing error:&error byAccessor:^(NSURL* destination) {
            written = [data writeToURL:destination options:NSDataWritingAtomic error:&write_error];
          }];
          if (written && error == nil) result = exported_result_(target);
          else if (error == nil) error = write_error;
        }
        if (scoped) [target stopAccessingSecurityScopedResource];
      }
      if (result.path.empty()) result.error = error != nil ? error.localizedDescription.UTF8String : "无法更新原文件，请使用另存。";
      std::lock_guard<std::mutex> lock(state->mutex);
      if (!state->pending) return;
      state->result = std::move(result);
      state->pending = false;
      state->ready = true;
    }
  });
  return true;
}

void IOSSGFFileBridge::cancel() {
  auto state = state_;
  dispatch_async(dispatch_get_main_queue(), ^{
    std::lock_guard<std::mutex> lock(state->mutex);
    state->pending = false;
    state->ready = false;
    [state->picker dismissViewControllerAnimated:YES completion:nil];
  });
}

godot::Dictionary IOSSGFFileBridge::poll_result() {
  std::lock_guard<std::mutex> lock(state_->mutex);
  if (!state_->ready) return {};
  state_->ready = false;
  return result_dictionary_(state_->result);
}

godot::Array IOSSGFFileBridge::poll_external_files() {
  godot::Array result;
  Class receiver = NSClassFromString(@"GotepadSGFOpenReceiver");
  if (receiver == Nil || ![receiver respondsToSelector:@selector(drain_results)]) return result;
  for (NSDictionary* imported in [receiver drain_results]) {
    IOSSGFResult value;
    value.path = [imported[@"path"] UTF8String];
    value.source_path = [(imported[@"source_path"] ?: @"") UTF8String];
    value.error = [imported[@"error"] UTF8String];
    result.append(result_dictionary_(value));
  }
  return result;
}
