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

#import "LuTorrentBridge.h"

#import <Flutter/Flutter.h>

// libtorrent 1.2.x（预制 xcframework + boost 头文件，路径见 Podfile/pbxproj）
#import "libtorrent/session.hpp"
#import "libtorrent/alert.hpp"
#import "libtorrent/alert_types.hpp"
#import "libtorrent/torrent_handle.hpp"
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/add_torrent_params.hpp"
#import "libtorrent/magnet_uri.hpp"

#include <memory>
#include <vector>
#include <string>

namespace lt = libtorrent;

@implementation LuTorrentBridge {
    lt::session *_session;
    lt::torrent_handle _handle;
    FlutterMethodChannel *_methodChannel;
    FlutterEventSink _eventSink;
    BOOL _gotMetadata;
    NSString *_mainFilePath;
    NSString *_mainFileName;
    long long _mainFileOffset;
    long long _mainFileSize;
    int _pieceLength;
    int _numPieces;
    int _mainFileIndex;
    NSThread *_alertThread;
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
        _session = nullptr;
        _gotMetadata = NO;
        _mainFileIndex = -1;
        _mainFileOffset = 0;
        _mainFileSize = 0;
        _pieceLength = 0;
        _numPieces = 0;
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
    if (!_eventSink) return;
    NSMutableDictionary *payload = [args mutableCopy] ?: [NSMutableDictionary dictionary];
    payload[@"event"] = event;
    _eventSink(payload);
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

    NSString *trimmed = [source stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL isMagnet = [[trimmed lowercaseString] hasPrefix:@"magnet:"];
    BOOL isTorrentURL = [[trimmed lowercaseString] hasPrefix:@"http"] &&
                        [[[NSURL URLWithString:trimmed] path] hasSuffix:@".torrent"];
    if (!isMagnet && !isTorrentURL) return NO;

    @try {
        _session = new lt::session();
        _session->set_alert_mask(lt::alert::all_categories);

        lt::add_torrent_params params;
        params.save_path = [saveDirPath UTF8String];
        // 边下边播：顺序下载优先。
        params.flags |= lt::torrent_flags::sequential_download;

        if (isMagnet) {
            lt::error_code ec;
            params = lt::parse_magnet_uri([trimmed UTF8String], ec);
            if (ec) {
                [self emit:@"error" args:@{@"message": @"磁力链接解析失败"}];
                return NO;
            }
            params.save_path = [saveDirPath UTF8String];
            params.flags |= lt::torrent_flags::sequential_download;
        } else {
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:trimmed]];
            if (!data || data.length == 0) {
                [self emit:@"error" args:@{@"message": @"种子文件下载失败"}];
                return NO;
            }
            std::shared_ptr<lt::torrent_info> ti =
                std::make_shared<lt::torrent_info>((const char *)data.bytes, (int)data.length);
            params.ti = ti;
        }

        _handle = _session->add_torrent(params);
        if (!_handle.is_valid()) {
            [self emit:@"error" args:@{@"message": @"添加种子失败"}];
            return NO;
        }
        [self emit:@"added" args:@{}];
        [self startAlertLoop];
        return YES;
    } @catch (...) {
        [self emit:@"error" args:@{@"message": @"种子会话异常"}];
        return NO;
    }
}

/// 后台线程轮询 alert：metadata_received_alert 里挑主文件。
- (void)startAlertLoop {
    _alertThread = [[NSThread alloc] initWithTarget:self
                                           selector:@selector(alertLoop)
                                             object:nil];
    [_alertThread setName:@"lu.torrent.alerts"];
    [_alertThread start];
}

- (void)alertLoop {
    @autoreleasepool {
        while (_session != nullptr) {
            @autoreleasepool {
                _session->wait_for_alert(std::chrono::milliseconds(300));
                std::vector<lt::alert *> alerts = _session->pop_alerts();
                for (lt::alert *a : alerts) {
                    std::unique_ptr<lt::alert> holder(a);
                    // 元数据就绪
                    if (lt::alert_cast<lt::metadata_received_alert>(a)) {
                        [self performSelectorOnMainThread:@selector(onMetadataReady)
                                               withObject:nil waitUntilDone:NO];
                    }
                    if (lt::alert_cast<lt::metadata_failed_alert>(a)) {
                        [self performSelectorOnMainThread:@selector(onMetadataFailed)
                                               withObject:nil waitUntilDone:NO];
                    }
                    if (lt::alert_cast<lt::torrent_error_alert>(a)) {
                        [self performSelectorOnMainThread:@selector(onTorrentError)
                                               withObject:nil waitUntilDone:NO];
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    }
}

- (void)onMetadataFailed {
    [self emit:@"metadata_failed" args:@{}];
}

- (void)onTorrentError {
    [self emit:@"error" args:@{@"message": @"种子下载错误"}];
}

- (void)onMetadataReady {
    if (_gotMetadata || !_handle.is_valid()) return;
    std::shared_ptr<lt::torrent_info> ti = _handle.torrent_file();
    if (!ti) return;

    lt::file_storage files = ti->files();
    int count = files.num_files();
    long long bestSize = 0;
    int best = 0;
    for (int i = 0; i < count; i++) {
        long long s = files.file_size(i);
        if (s > bestSize) { bestSize = s; best = i; }
    }
    if (bestSize <= 0) return;

    _gotMetadata = YES;
    _mainFileIndex = best;
    _mainFileSize = bestSize;
    _mainFileOffset = files.file_offset(best);
    _pieceLength = ti->piece_length();
    _numPieces = ti->num_pieces();

    std::string name = files.file_name(best);
    _mainFileName = [NSString stringWithUTF8String:name.c_str()] ?: @"video";
    std::string relPath = files.file_path(best);
    NSString *savePath = [NSString stringWithUTF8String:_handle.save_path().c_str()];
    NSString *fullPath = [NSString stringWithFormat:@"%@/%@", savePath,
                          [NSString stringWithUTF8String:relPath.c_str()]];
    _mainFilePath = [[fullPath stringByStandardizingPath] copy];

    // 只下主文件，其余 IGNORE。
    std::vector<lt::download_priority_t> priorities(ti->num_files(), lt::dont_download);
    if (best < (int)priorities.size()) priorities[best] = lt::default_priority;
    _handle.prioritize_files(priorities);

    // 1.2.x 没有 set_sequential_range（那是 2.x API）；
    // sequential_download 标志已在 add_torrent 时设置，这里靠分片 deadline 引导。

    [self emit:@"metadata" args:@{@"name": _mainFileName}];
}

- (void)stopSession {
    if (_session != nullptr) {
        delete _session;
        _session = nullptr;
    }
    _handle = lt::torrent_handle();
    _gotMetadata = NO;
    _alertThread = nil;
}

#pragma mark - 查询接口

- (NSDictionary *)fileInfo {
    if (!_gotMetadata) return @{};
    return @{
        @"fileName": _mainFileName,
        @"fileSize": @(_mainFileSize),
        @"fileOffset": @(_mainFileOffset),
        @"pieceLength": @(_pieceLength),
        @"numPieces": @(_numPieces),
        @"path": _mainFilePath,
    };
}

- (NSDictionary *)status {
    if (!_handle.is_valid() || !_gotMetadata) {
        return @{@"progress": @(0.0), @"speed": @(0), @"peers": @(0), @"state": @"fetching"};
    }
    @try {
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
    } @catch (...) {
        return @{@"progress": @(0.0), @"speed": @(0), @"peers": @(0), @"state": @"unknown"};
    }
}

- (NSArray<NSNumber *> *)piecesForStart:(long long)start end:(long long)end {
    if (_pieceLength <= 0) return @[];
    long long absStart = _mainFileOffset + start;
    long long absEnd = _mainFileOffset + end;
    int p0 = (int)(absStart / _pieceLength);
    int p1 = (int)(absEnd / _pieceLength);
    if (p1 < p0) p1 = p0;
    if (p1 >= _numPieces) p1 = _numPieces - 1;
    NSMutableArray *out = [NSMutableArray array];
    for (int p = p0; p <= p1; p++) [out addObject:@(p)];
    return out;
}

- (BOOL)prioritizeFrom:(long long)start to:(long long)end {
    if (!_handle.is_valid() || !_gotMetadata) return NO;
    @try {
        for (NSNumber *n in [self piecesForStart:start end:end]) {
            int p = n.intValue;
            if (!_handle.have_piece(lt::piece_index_t(p))) {
                // 1.2.x 签名：set_piece_deadline(piece_index_t, int, deadline_flags_t)
                // 用默认 flags（0_bit 即 alert_when_available），避免类型歧义。
                _handle.set_piece_deadline(lt::piece_index_t(p), 5000);
            }
        }
        return YES;
    } @catch (...) {
        return NO;
    }
}

- (BOOL)isReadyFrom:(long long)start to:(long long)end {
    if (!_handle.is_valid() || !_gotMetadata) return NO;
    @try {
        for (NSNumber *n in [self piecesForStart:start end:end]) {
            if (!_handle.have_piece(lt::piece_index_t(n.intValue))) return NO;
        }
        return YES;
    } @catch (...) {
        return NO;
    }
}

@end
