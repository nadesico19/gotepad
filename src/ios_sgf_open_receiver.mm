#include "ios_sgf_import.hpp"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// This class is statically linked into the app. +load runs before UIApplicationMain,
// so cold-start connectionOptions are captured before Godot loads its GDExtensions.
@interface GotepadSGFOpenReceiver : NSObject
+ (void)receive_urls_:(NSSet<UIOpenURLContext*>*)contexts;
+ (BOOL)receive_url_:(NSURL*)url;
+ (NSMutableArray<NSDictionary*>*)results_;
+ (NSArray<NSDictionary*>*)drain_results;
+ (void)trace_:(NSString*)stage url:(NSURL*)url error:(NSString*)error;
@end

@implementation GotepadSGFOpenReceiver
+ (void)trace_:(NSString*)stage url:(NSURL*)url error:(NSString*)error {
  @synchronized(self) {
    NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString* directory = [documents stringByAppendingPathComponent:@".tmp"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* path = [directory stringByAppendingPathComponent:@"sgf-open-events.jsonl"];
    NSDictionary* entry = @{@"time": @(NSDate.date.timeIntervalSince1970), @"stage": stage,
      @"url": url.absoluteString ?: @"", @"source_path": ios_sgf_source_path(url), @"error": error ?: @""};
    NSData* json = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
    if (json == nil) return;
    NSMutableData* line = [json mutableCopy];
    [line appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) [NSData.data writeToFile:path atomically:YES];
    NSFileHandle* file = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:path] error:nil];
    unsigned long long offset = 0;
    if ([file seekToEndReturningOffset:&offset error:nil]) {
      // Keep a bounded diagnostic file; no chess content is recorded.
      if (offset > 512 * 1024) {
        [file truncateAtOffset:0 error:nil];
        [file seekToOffset:0 error:nil];
      }
      [file writeData:line error:nil];
    }
    [file closeAndReturnError:nil];
  }
}
+ (NSMutableArray<NSDictionary*>*)results_ {
  static NSMutableArray<NSDictionary*>* results = [NSMutableArray new];
  return results;
}
+ (BOOL)receive_url_:(NSURL*)url {
  // Persist the incoming URL before validation, including percent-encoded filenames.
  [self trace_:@"received" url:url error:nil];
  if (!url.isFileURL || ![url.pathExtension.lowercaseString isEqualToString:@"sgf"]) return NO;
  NSDictionary* result = import_ios_sgf(url);
  [self trace_:@"import_finished" url:url error:result[@"error"]];
  @synchronized(self) {
    [[self results_] addObject:result];
  }
  return YES;
}
+ (void)receive_urls_:(NSSet<UIOpenURLContext*>*)contexts {
  for (UIOpenURLContext* context in contexts) [self receive_url_:context.URL];
}
+ (NSArray<NSDictionary*>*)drain_results {
  @synchronized(self) {
    NSArray<NSDictionary*>* result = [[self results_] copy];
    [[self results_] removeAllObjects];
    return result;
  }
}
+ (void)load {
  Class delegate = NSClassFromString(@"GDTApplicationDelegate");
  if (delegate == Nil) delegate = NSClassFromString(@"GDTAppDelegate");
  Method connect = class_getInstanceMethod(delegate, @selector(scene:willConnectToSession:options:));
  Method open = class_getInstanceMethod(delegate, @selector(scene:openURLContexts:));
  Method legacy = class_getInstanceMethod(delegate, @selector(application:openURL:options:));
  if (connect == nullptr || open == nullptr || legacy == nullptr) {
    NSLog(@"Gotepad: iOS SGF receiver could not find Godot lifecycle methods.");
    return;
  }
  IMP original_connect = method_getImplementation(connect);
  method_setImplementation(connect, imp_implementationWithBlock(^(id object, UIScene* scene, UISceneSession* session, UISceneConnectionOptions* options) {
    [GotepadSGFOpenReceiver receive_urls_:options.URLContexts];
    ((void (*)(id, SEL, UIScene*, UISceneSession*, UISceneConnectionOptions*))original_connect)(object, @selector(scene:willConnectToSession:options:), scene, session, options);
  }));
  IMP original_open = method_getImplementation(open);
  method_setImplementation(open, imp_implementationWithBlock(^(id object, UIScene* scene, NSSet<UIOpenURLContext*>* contexts) {
    [GotepadSGFOpenReceiver receive_urls_:contexts];
    ((void (*)(id, SEL, UIScene*, NSSet<UIOpenURLContext*>*))original_open)(object, @selector(scene:openURLContexts:), scene, contexts);
  }));
  IMP original_legacy = method_getImplementation(legacy);
  method_setImplementation(legacy, imp_implementationWithBlock(^BOOL(id object, UIApplication* application, NSURL* url, NSDictionary* options) {
    if ([GotepadSGFOpenReceiver receive_url_:url]) return YES;
    return ((BOOL (*)(id, SEL, UIApplication*, NSURL*, NSDictionary*))original_legacy)(object, @selector(application:openURL:options:), application, url, options);
  }));
}
@end

// Referenced by Godot's generated plugin glue, retaining this object in the executable.
void initialize_gotepad_sgf_receiver() {}
void deinitialize_gotepad_sgf_receiver() {}
