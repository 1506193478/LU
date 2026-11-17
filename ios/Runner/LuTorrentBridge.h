//
//  LuTorrentBridge.h
//  Runner
//
//  磁力播放的 iOS 原生桥（Objective-C++ 调 libtorrent 1.2 C++ API）。
//  协议与 Android 侧 TorrentEngine.kt 完全一致：
//    MethodChannel `lu/torrent`:
//      start(magnet, saveDir) / fileInfo / status / prioritize(start,end)
//      isReady(start,end) / stop
//    EventChannel `lu/torrent/events`:
//      metadata / metadata_failed / added / error
//
//  由 AppDelegate.swift 通过 Runner-Bridging-Header.h 引用并注册。
//

#import <Foundation/Foundation.h>

@protocol FlutterBinaryMessenger;
@protocol FlutterStreamHandler;
@class FlutterMethodChannel;

NS_ASSUME_NONNULL_BEGIN

/// 注册 MethodChannel / EventChannel 到给定 engine。
/// 在 configureFlutterEngine 里调用一次。
@interface LuTorrentBridge : NSObject <FlutterStreamHandler>

/// messenger 传 flutterEngine.dartExecutor.binaryMessenger。
+ (void)registerWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;

/// 页面退出时清理会话（可选，stop 方法也会调）。
+ (void)dispose;

@end

NS_ASSUME_NONNULL_END
