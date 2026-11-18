import AVKit
import UIKit

/// 画中画。AVPlayerLayer 直接喂给 `AVPictureInPictureController`，
/// 退出到桌面/切换 App 时视频继续浮动播放。
///
/// 前置条件：`Audio, AirPlay, and Picture in Picture` 后台能力（Info.plist
/// `UIBackgroundModes` 含 `audio`）+ 音频会话 `.playback`，两者本项目都已具备。
final class LuPiPController: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = LuPiPController()

    private var controller: AVPictureInPictureController?
    private weak var layer: AVPlayerLayer?

    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    var isAvailable: Bool { isSupported && layer != nil }
    var isActive: Bool { controller?.isPictureInPictureActive ?? false }

    func attach(_ playerLayer: AVPlayerLayer) {
        guard playerLayer !== layer else { return }
        layer = playerLayer
        guard isSupported else { return }
        let controller = AVPictureInPictureController(playerLayer: playerLayer)
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller
    }

    func toggle() {
        guard let controller else {
            LuHUD.shared.show("当前视频暂不支持画中画")
            return
        }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    func stop() {
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    // MARK: AVPictureInPictureControllerDelegate

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        luLogInfo("Player", "进入画中画")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        luLogInfo("Player", "退出画中画")
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        luLogWarn("Player", "画中画启动失败：\(error.localizedDescription)")
        LuHUD.shared.show("画中画启动失败")
    }
}
