#!/usr/bin/env bash
# 一键发布：格式化 → 静态检查 → 全量测试 → 构建 → 归档产物
#
# 用法：
#   ./tool/release.sh              # 完整流程（含测试与构建）
#   ./tool/release.sh --no-build   # 只跑检查与测试
#
# 产物：build/app/outputs/flutter-apk/app-release.apk
set -uo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WS"

# Flutter 环境（按需覆盖）
export PATH="$HOME/flutter/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-/root/Android}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

STEP=0
step() { STEP=$((STEP + 1)); echo; echo "===== [$STEP] $* ====="; }
fail() { echo; echo "❌ $*"; exit 1; }

VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
APP_VERSION="$(grep -E 'static const String version' lib/src/app_info.dart | awk -F"'" '{print $2}')"
echo "樱读 发布流程 · 版本 $VERSION"

step "版本一致性（pubspec ↔ 关于页）"
[[ "${VERSION%%+*}" == "$APP_VERSION" ]] ||
  fail "版本不同步：pubspec=${VERSION%%+*}，app_info=$APP_VERSION（两处一起改，见 CONTRIBUTING）"
echo "✓ 一致：${VERSION%%+*}"

step "代码格式化（应为 0 改动）"
BEFORE="$(dart format lib test | tail -1)"
echo "$BEFORE"
case "$BEFORE" in
  *"0 changed"*) ;;
  *) echo "⚠️  格式化改动了文件，请提交后再发布" ;;
esac

step "静态检查"
flutter analyze || fail "flutter analyze 未通过"

step "单元 / Widget 测试"
flutter test || fail "flutter test 未通过"

if [[ "${1:-}" == "--no-build" ]]; then
  echo; echo "✅ 检查与测试通过（已跳过构建）"
  exit 0
fi

step "构建 release APK（单架构 arm64）"
flutter build apk --release --target-platform android-arm64 || fail "构建失败"

APK="build/app/outputs/flutter-apk/app-release.apk"
[[ -f "$APK" ]] || fail "未找到构建产物：$APK"

step "产物信息"
ls -la "$APK"
echo
echo "✅ 发布就绪"
echo "   APK    : $APK"
echo "   版本   : $VERSION"
echo "   建议归档为：樱读-v${VERSION%%+*}.apk"
echo
echo "   装机（adb / 本机）：adb install -r $APK"
