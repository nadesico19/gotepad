#pragma once

#import <Foundation/Foundation.h>

// Normalize only the comparison key; filesystem access always uses the original URL.
inline NSString* ios_sgf_source_path(NSURL* url) {
  return url.URLByStandardizingPath.URLByResolvingSymlinksInPath.path.precomposedStringWithCanonicalMapping ?: @"";
}

// Coordinate provider access and preserve the filename in an isolated import folder.
inline NSDictionary* import_ios_sgf(NSURL* url) {
  if (url == nil || !url.isFileURL || ![url.pathExtension.lowercaseString isEqualToString:@"sgf"])
    return @{@"path": @"", @"error": @"请选择 .sgf 棋谱文件。", @"cancelled": @NO};
  BOOL scoped = [url startAccessingSecurityScopedResource];
  NSError* coordination_error = nil;
  __block NSError* copy_error = nil;
  __block NSURL* target = nil;
  NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
  [coordinator coordinateReadingItemAtURL:url options:0 error:&coordination_error byAccessor:^(NSURL* source) {
    NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString* directory = [[documents stringByAppendingPathComponent:@".tmp/sgf-import"] stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&copy_error]) return;
    NSURL* destination = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:url.lastPathComponent]];
    if ([[NSFileManager defaultManager] copyItemAtURL:source toURL:destination error:&copy_error]) target = destination;
  }];
  if (scoped) [url stopAccessingSecurityScopedResource];
  NSError* error = coordination_error ?: copy_error;
  return @{@"path": target.path ?: @"", @"source_path": ios_sgf_source_path(url), @"error": target != nil ? @"" : (error.localizedDescription ?: @"无法导入 SGF 文件。"), @"cancelled": @NO};
}
