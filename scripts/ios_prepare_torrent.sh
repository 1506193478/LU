#!/usr/bin/env bash
# 下载 iOS 磁力播放依赖：libtorrent 1.2.17 预制 xcframework + boost 头文件。
#
# 设计：
#   * 二进制大件不进 Git（186MB xcframework + ~130MB boost headers）；
#   * CI（ios.yml）在 flutter build 前跑本脚本，下载后直接被 Xcode 引用；
#   * 本地开发若需要编译 iOS，也手动跑一次本脚本。
#
# 来源：
#   * libtorrent-Apple 1.2.17 (danylokos) — libtorrent BSD-3-Clause，预制二进制
#   * boost 1.69.0 — BSL-1.0（libtorrent 头文件 #include <boost/...> 必需）
#     从 SwiftyTorrent bootstrap.sh 同款存档下载。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/ios/Thirdparties"
LT_VER="1.2.17"
BOOST_VER="1.69.0"

mkdir -p "$DEST"

# ---- libtorrent.xcframework ----
if [ ! -d "$DEST/libtorrent.xcframework" ]; then
  echo "[lu] downloading libtorrent $LT_VER xcframework..."
  curl -fsSL --retry 3 --connect-timeout 30 \
    -o "$DEST/libtorrent.xcframework.zip" \
    "https://github.com/danylokos/libtorrent-Apple/releases/download/$LT_VER/libtorrent.xcframework.zip"
  unzip -q "$DEST/libtorrent.xcframework.zip" -d "$DEST"
  rm -f "$DEST/libtorrent.xcframework.zip"
fi

# ---- boost headers（libtorrent 1.2 头文件依赖 <boost/...>）----
if [ ! -d "$DEST/boost-$BOOST_VER/boost" ]; then
  echo "[lu] downloading boost $BOOST_VER headers..."
  mkdir -p "$DEST/boost-$BOOST_VER"
  BOOST_UNDERSCORE="1_69_0"
  curl -fsSL --retry 3 --connect-timeout 30 \
    -o "$DEST/boost.tar.gz" \
    "https://archives.boost.io/release/$BOOST_VER/source/boost_${BOOST_UNDERSCORE}.tar.gz"
  tar -xzf "$DEST/boost.tar.gz" \
    -C "$DEST/boost-$BOOST_VER" --strip-components=1 \
    "boost_${BOOST_UNDERSCORE}/boost"
  rm -f "$DEST/boost.tar.gz"
fi

echo "[lu] iOS torrent deps ready at $DEST"
ls -d "$DEST/libtorrent.xcframework" "$DEST/boost-$BOOST_VER/boost"
