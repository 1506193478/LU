//
//  LuTorrentBridge.mm
//  Runner
//
//  iOS 磁力播放原生桥：Objective-C++ 直接调 libtorrent 1.2.x C++ API。
//  协议与 Android 的 TorrentEngine.kt 完全一致（见 LuTorrentBridge.h）。
//
//  刻意不照搬 SwiftyTorrent 的 TorrentKit 源码（那个仓库无 license）；
//  这里只用 libtorrent 官方 API（BSD 许可），避免第三方源码版权风险。
//
//  ⚠️ 线程模型（4.2.3 重写，修闪退）：
//   1. session 用 shared_ptr 持有：alert 泵只持一份副本，stop 时 reset 也不会
//      use-after-free（旧版直接 delete 裸指针，泵线程还在 wait_for_alert → 崩）。
//   2. alert 泵从「独立 NSThread + sleep」改成「串行 dispatch 队列 + 定时器」：
//      stop 时 cancel + dispatch_sync 排空，绝不与 session 析构并发。
//   3. **所有 libtorrent 调用一律用 C++ try/catch**（旧版用 @try/@catch，
//      Objective-C 的 @catch 只捕 ObjC 异常，C++ 异常会穿透 → std::terminate
//      直接闪退；这是「点播放就崩」的主因）。
//   4. emit 一律切主线程（FlutterEventSink 不是线程安全的）。
//

#import "LuTorrentBridge.h"

#import <Flutter/Flutter.h>

// libtorrent 1.2.x（预制 xcframework + boost 头文件，路径见 pbxproj）
#import "libtorrent/session.hpp"
#import "libtorrent/alert.hpp"
#import "libtorrent/alert_types.hpp"
#import "libtorrent/torrent_handle.hpp"
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/add_torrent_params.hpp"
#import "libtorrent/magnet_uri.hpp"
#import "libtorrent/settings_pack.hpp"
#import "libtorrent/error_code.hpp"

#include <chrono>
#include <memory>
#include <mutex>
#include <vector>
#include <string>
#include <system_error>

namespace lt = libtorrent;

@implementation LuTorrentBridge {
    std::shared_ptr<lt::session> _session;
    lt::torrent_handle _handle;
    std::mutex _mutex;

    FlutterMethodChannel *_methodChannel;
    FlutterEventSink _eventSink;

    dispatch_queue_t _alertQueue;
    dispatch_source_t _alertTimer;

    BOOL _gotMetadata;
    NSString *_mainFilePath;
    NSString *_mainFileName;
    long long _mainFileOffset;
    long long _mainFileSize;
    int _pieceLength;
    int _numPieces;
    int _mainFileIndex;
}

#pragma mark - 生命周期

+ (void)registerWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    static dispatch_once_t onceToken;
    static LuTorrentBridge *bridge;
    dispatch_once(&onceToken, ^{
        bridge = [[LuTorrentBridge alloc] initWithMessenger:messenger];
    });
    // messenger 可能重建（热重启），始终重绑通道。
    [bridge bindMessenger:messenger];
}

+ (void)dispose {
    // 由 stop 方法负责；这里不主动销毁单例。
}

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    if (self) {
        _gotMetadata = NO;
        _mainFileIndex = -1;
        _mainFileOffset = 0;
        _mainFileSize = 0;
        _pieceLength = 0;
        _numPieces = 0;
        _mainFileName = @"";
        _mainFilePath = @"";
        [self bindMessenger:messenger];
    }
    return self;
}

- (void)bindMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    _methodChannel = [FlutterMethodChannel
        methodChannelWithName:@"lu/torrent"
              binaryMessenger:messenger];
    __weak typeof(self) weakSelf = self;
    [_methodChannel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
        [weakSelf handleCall:call result:result];
    }];

    FlutterEventChannel *eventChannel = [FlutterEventChannel
        eventChannelWithName:@"lu/torrent/events"
              binaryMessenger:messenger];
    [eventChannel setStreamHandler:self];
}

- (void)dealloc {
    [self stopSession];
}

#pragma mark - FlutterStreamHandler

- (FlutterError *)onListenWithArguments:(id)arguments
                              eventSink:(FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
    _eventSink = nil;
    return nil;
}

- (void)emit:(NSString *)event args:(NSDictionary *)args {
    NSMutableDictionary *payload = [(args ?: @{}) mutableCopy];
    payload[@"event"] = event;

    void (^send)(void) = ^{
        FlutterEventSink sink = self->_eventSink;
        if (!sink) return;
        sink(payload);
    };
    if ([NSThread isMainThread]) {
        send();
    } else {
        dispatch_async(dispatch_get_main_queue(), send);
    }
}

#pragma mark - MethodChannel 分派

- (void)handleCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"start"]) {
        NSString *magnet = call.arguments[@"magnet"] ?: @"";
        NSString *saveDir = call.arguments[@"saveDir"] ?: @"";
        BOOL ok = [self startSession:magnet saveDir:saveDir];
        result(@(ok));
    } else if ([call.method isEqualToString:@"fileInfo"]) {
        result([self fileInfo]);
    } else if ([call.method isEqualToString:@"status"]) {
        result([self status]);
    } else if ([call.method isEqualToString:@"prioritize"]) {
        long long start = [call.arguments[@"start"] longLongValue];
        long long end = [call.arguments[@"end"] longLongValue];
        result(@([self prioritizeFrom:start to:end]));
    } else if ([call.method isEqualToString:@"isReady"]) {
        long long start = [call.arguments[@"start"] longLongValue];
        long long end = [call.arguments[@"end"] longLongValue];
        result(@([self isReadyFrom:start to:end]));
    } else if ([call.method isEqualToString:@"stop"]) {
        [self stopSession];
        result(@(YES));
    } else {
        result(FlutterMethodNotImplemented);
    }
}

#pragma mark - 会话管理

- (BOOL)startSession:(NSString *)source saveDir:(NSString *)saveDirPath {
    [self stopSession];
    _gotMetadata = NO;
    _mainFileIndex = -1;
    _mainFileName = @"";
    _mainFilePath = @"";
    _mainFileOffset = 0;
    _mainFileSize = 0;
    _pieceLength = 0;
    _numPieces = 0;

    NSString *trimmed = [source
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL isMagnet = [[trimmed lowercaseString] hasPrefix:@"magnet:"];
    BOOL isTorrentURL = [[trimmed lowercaseString] hasPrefix:@"http"] &&
                        [[[NSURL URLWithString:trimmed] path] hasSuffix:@".torrent"];
    if (!isMagnet && !isTorrentURL) {
        [self emit:@"error" args:@{@"message": @"不是磁力链接或种子地址"}];
        return NO;
    }

    // 保存目录必须存在，否则 libtorrent 建文件失败会抛异常。
    if (saveDirPath.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:saveDirPath
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:NULL];
    }

    std::shared_ptr<lt::session> session;
    lt::torrent_handle handle;

    try {
        // iOS 上把 libtorrent 的初始化路径压到最保守：
        //   * 显式指定监听地址（默认会去绑 0.0.0.0/[::]，沙盒下容易出岔子）；
        //   * 关掉 UPnP / NAT-PMP / LSD（iOS 不需要，且都要额外的系统权限）；
        //   * DHT 保留（磁力靠它找 peer）。
        // 这些设置一改，session 构造时不再碰路由器相关的系统 API。
        lt::settings_pack pack;
        pack.set_str(lt::settings_pack::listen_interfaces, "0.0.0.0:6881");
        pack.set_bool(lt::settings_pack::enable_upnp, false);
        pack.set_bool(lt::settings_pack::enable_natpmp, false);
        pack.set_bool(lt::settings_pack::enable_lsd, false);
        pack.set_bool(lt::settings_pack::enable_dht, true);
        pack.set_int(lt::settings_pack::alert_mask, lt::alert::all_categories);

        session = std::make_shared<lt::session>(pack);
        session->set_alert_mask(lt::alert::all_categories);

        lt::add_torrent_params params;
        params.save_path = std::string([saveDirPath UTF8String] ?: "");
        // 边下边播：顺序下载优先。
        params.flags |= lt::torrent_flags::sequential_download;

        if (isMagnet) {
            lt::error_code ec;
            params = lt::parse_magnet_uri(std::string([trimmed UTF8String] ?: ""), ec);
            if (ec) {
                [self emit:@"error" args:@{@"message": @"磁力链接解析失败"}];
                return NO;
            }
            params.save_path = std::string([saveDirPath UTF8String] ?: "");
            params.flags |= lt::torrent_flags::sequential_download;
        } else {
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:trimmed]];
            if (data.length == 0) {
                [self emit:@"error" args:@{@"message": @"种子文件下载失败"}];
                return NO;
            }
            lt::error_code ec;
            // 带 error_code 的构造不会抛异常（旧版用的是会抛的版本）。
            auto ti = std::make_shared<lt::torrent_info>(
                (const char *)data.bytes, (int)data.length, ec);
            if (ec) {
                [self emit:@"error" args:@{@"message": @"种子文件解析失败"}];
                return NO;
            }
            params.ti = ti;
        }

        handle = session->add_torrent(params);
        if (!handle.is_valid()) {
            [self emit:@"error" args:@{@"message": @"添加种子失败"}];
            return NO;
        }
    } catch (std::exception const &e) {
        [self emit:@"error" args:@{@"message": [NSString stringWithFormat:@"种子会话异常：%s", e.what()]}];
        return NO;
    } catch (...) {
        [self emit:@"error" args:@{@"message": @"种子会话异常"}];
        return NO;
    }

    {
        std::lock_guard<std::mutex> lock(_mutex);
        _session = session;
        _handle = handle;
    }

    [self emit:@"added" args:@{}];
    [self startAlertTimer];
    return YES;
}

/// 串行队列 + 定时器泵 alert。比旧版「独立线程 sleep」好在能同步排空，
/// stop 时绝不会和 session 析构并发。
- (void)startAlertTimer {
    [self stopAlertTimer];

    _alertQueue = dispatch_queue_create("lu.torrent.alerts", DISPATCH_QUEUE_SERIAL);
    _alertTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _alertQueue);
    dispatch_source_set_timer(_alertTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              100ull * NSEC_PER_MSEC,
                              20ull * NSEC_PER_MSEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_alertTimer, ^{
        [weakSelf pumpAlerts];
    });
    dispatch_resume(_alertTimer);
}

- (void)stopAlertTimer {
    if (_alertTimer) {
        dispatch_source_cancel(_alertTimer);
        _alertTimer = nil;
    }
    dispatch_queue_t q = _alertQueue;
    _alertQueue = nil;
    if (q) {
        // 排空队列：等正在跑的 handler 结束（最多一次 wait_for_alert 的时间）。
        dispatch_sync(q, ^{
        });
    }
}

- (void)pumpAlerts {
    std::shared_ptr<lt::session> session;
    {
        std::lock_guard<std::mutex> lock(_mutex);
        session = _session;
    }
    if (!session) return;

    BOOL gotMetadata = NO;
    BOOL metadataFailed = NO;
    BOOL torrentError = NO;

    try {
        session->wait_for_alert(std::chrono::milliseconds(30));
        std::vector<lt::alert *> alerts;
        session->pop_alerts(&alerts);
        for (lt::alert *a : alerts) {
            std::unique_ptr<lt::alert> holder(a);
            if (lt::alert_cast<lt::metadata_received_alert>(a)) gotMetadata = YES;
            if (lt::alert_cast<lt::metadata_failed_alert>(a)) metadataFailed = YES;
            if (lt::alert_cast<lt::torrent_error_alert>(a)) torrentError = YES;
        }
    } catch (...) {
        // session 正在析构 / 内部异常：本轮直接跳过，下一轮再看。
        return;
    }

    if (gotMetadata) {
        [self performSelectorOnMainThread:@selector(onMetadataReady)
                               withObject:nil
                            waitUntilDone:NO];
    }
    if (metadataFailed) {
        [self performSelectorOnMainThread:@selector(onMetadataFailed)
                               withObject:nil
                            waitUntilDone:NO];
    }
    if (torrentError) {
        [self performSelectorOnMainThread:@selector(onTorrentError)
                               withObject:nil
                            waitUntilDone:NO];
    }
}

- (void)onMetadataFailed {
    [self emit:@"metadata_failed" args:@{}];
}

- (void)onTorrentError {
    [self emit:@"error" args:@{@"message": @"种子下载错误"}];
}

- (void)onMetadataReady {
    if (_gotMetadata) return;

    try {
        std::lock_guard<std::mutex> lock(_mutex);
        if (!_handle.is_valid()) return;
        std::shared_ptr<const lt::torrent_info> ti = _handle.torrent_file();
        if (!ti) return;

        lt::file_storage files = ti->files();
        int count = files.num_files();
        if (count <= 0) return;

        long long bestSize = 0;
        int best = 0;
        for (int i = 0; i < count; i++) {
            long long s = files.file_size(i);
            if (s > bestSize) {
                bestSize = s;
                best = i;
            }
        }
        if (bestSize <= 0) return;

        _gotMetadata = YES;
        _mainFileIndex = best;
        _mainFileSize = bestSize;
        _mainFileOffset = files.file_offset(best);
        _pieceLength = ti->piece_length();
        _numPieces = ti->num_pieces();

        lt::string_view nameView = files.file_name(best);
        std::string name(nameView.begin(), nameView.end());
        _mainFileName = [NSString stringWithUTF8String:name.c_str()] ?: @"video";

        std::string relPath = files.file_path(best);
        std::string savePathCpp(_handle.save_path());
        NSString *savePath = [NSString stringWithUTF8String:savePathCpp.c_str()] ?: @"";
        NSString *fullPath = [NSString stringWithFormat:@"%@/%@", savePath,
                              [NSString stringWithUTF8String:relPath.c_str()] ?: @""];
        _mainFilePath = [[fullPath stringByStandardizingPath] copy];

        // 只下主文件，其余 IGNORE。
        std::vector<lt::download_priority_t> priorities(ti->num_files(), lt::dont_download);
        if (best < (int)priorities.size()) priorities[best] = lt::default_priority;
        _handle.prioritize_files(priorities);
    } catch (...) {
        return;
    }

    [self emit:@"metadata" args:@{@"name": _mainFileName ?: @"video"}];
}

- (void)stopSession {
    // 顺序很关键：先停泵（含排空），再解引用 session。
    [self stopAlertTimer];

    {
        std::lock_guard<std::mutex> lock(_mutex);
        if (_session) {
            try {
                _session->abort();
            } catch (...) {
            }
            _session.reset();
        }
        _handle = lt::torrent_handle();
    }

    _gotMetadata = NO;
    _mainFileName = @"";
    _mainFilePath = @"";
    _mainFileIndex = -1;
    _mainFileOffset = 0;
    _mainFileSize = 0;
    _pieceLength = 0;
    _numPieces = 0;
}

#pragma mark - 查询接口

- (NSDictionary *)fileInfo {
    if (!_gotMetadata) return @{};
    return @{
        @"fileName": _mainFileName ?: @"video",
        @"fileSize": @(_mainFileSize),
        @"fileOffset": @(_mainFileOffset),
        @"pieceLength": @(_pieceLength),
        @"numPieces": @(_numPieces),
        @"path": _mainFilePath ?: @"",
    };
}

- (NSDictionary *)status {
    if (!_gotMetadata) {
        return @{@"progress": @(0.0), @"speed": @(0), @"peers": @(0), @"state": @"fetching"};
    }
    try {
        std::lock_guard<std::mutex> lock(_mutex);
        if (!_handle.is_valid()) {
            return @{@"progress": @(0.0), @"speed": @(0), @"peers": @(0), @"state": @"fetching"};
        }
        lt::torrent_status st = _handle.status();
        double progress = st.progress;
        if (progress < 0) progress = 0;
        if (progress > 1) progress = 1;
        NSString *state = st.is_finished ? @"completed" : @"downloading";
        return @{
            @"progress": @(progress),
            @"speed": @(st.download_rate),
            @"peers": @(st.num_peers),
            @"state": state,
        };
    } catch (...) {
        return @{@"progress": @(0.0), @"speed": @(0), @"peers": @(0), @"state": @"unknown"};
    }
}

- (NSArray<NSNumber *> *)piecesForStart:(long long)start end:(long long)end {
    if (_pieceLength <= 0 || _numPieces <= 0) return @[];
    long long absStart = _mainFileOffset + start;
    long long absEnd = _mainFileOffset + end;
    int p0 = (int)(absStart / _pieceLength);
    int p1 = (int)(absEnd / _pieceLength);
    if (p1 < p0) p1 = p0;
    if (p0 < 0) p0 = 0;
    if (p1 >= _numPieces) p1 = _numPieces - 1;
    NSMutableArray *out = [NSMutableArray array];
    for (int p = p0; p <= p1; p++) [out addObject:@(p)];
    return out;
}

- (BOOL)prioritizeFrom:(long long)start to:(long long)end {
    if (!_gotMetadata) return NO;
    try {
        std::lock_guard<std::mutex> lock(_mutex);
        if (!_handle.is_valid()) return NO;
        for (NSNumber *n in [self piecesForStart:start end:end]) {
            int p = n.intValue;
            if (!_handle.have_piece(lt::piece_index_t(p))) {
                // 1.2.x 签名：set_piece_deadline(piece_index_t, int, deadline_flags_t)
                // 用默认 flags，避免类型歧义。
                _handle.set_piece_deadline(lt::piece_index_t(p), 5000);
            }
        }
        return YES;
    } catch (...) {
        return NO;
    }
}

- (BOOL)isReadyFrom:(long long)start to:(long long)end {
    if (!_gotMetadata) return NO;
    try {
        std::lock_guard<std::mutex> lock(_mutex);
        if (!_handle.is_valid()) return NO;
        for (NSNumber *n in [self piecesForStart:start end:end]) {
            if (!_handle.have_piece(lt::piece_index_t(n.intValue))) return NO;
        }
        return YES;
    } catch (...) {
        return NO;
    }
}

@end
