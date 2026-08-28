#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <pdfium-binaries-dir> <linux|mac|win> <x64|x86|arm64>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILDER_ROOT="$(cd "$1" && pwd)"
TARGET_OS="$2"
TARGET_CPU="$3"
PDFIUM_REVISION="99c42f5a6508f738383b5f3ab641959231360353"
DEPOT_TOOLS_REVISION="3d401c263f5b4ee534eacf967ac7234f7c4ee029"
CUSTOM_PATCH="$WRAPPER_ROOT/pdfium/patches/eagle_catalog_custom_stream.patch"
DEPOT_TOOLS_WINDOWS_PATCH="$WRAPPER_ROOT/pdfium/patches/depot_tools_windows_gsutil_cleanup.patch"

case "$TARGET_OS:$TARGET_CPU" in
  linux:x64|linux:arm64|mac:x64|mac:arm64|win:x86|win:x64) ;;
  *)
    echo "unsupported target: $TARGET_OS:$TARGET_CPU" >&2
    exit 2
    ;;
esac

cd "$BUILDER_ROOT"

export PDFium_TARGET_OS="$TARGET_OS"
export PDFium_TARGET_CPU="$TARGET_CPU"
export PDFium_TARGET_ENVIRONMENT=""
export PDFium_ENABLE_V8=false
export PDFium_IS_DEBUG=false
export PDFium_VERSION="7543.0.0.1"
export PDFium_SOURCE_DIR="$BUILDER_ROOT/pdfium"
export PDFium_BUILD_DIR="$BUILDER_ROOT/pdfium/out"
export DEPOT_TOOLS_WIN_TOOLCHAIN=0
export DEPOT_TOOLS_UPDATE=0

if [[ "$TARGET_OS" == "win" ]]; then
  export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
  export PYTHONUTF8=1
  export PYTHONIOENCODING=utf-8
  export PATH="$WRAPPER_ROOT/pdfium/scripts:$PATH"
fi

EAGLE_ENV_FILE="$BUILDER_ROOT/.eagle-env-$TARGET_OS-$TARGET_CPU"
EAGLE_PATH_FILE="$BUILDER_ROOT/.eagle-path-$TARGET_OS-$TARGET_CPU"
export GITHUB_ENV="$EAGLE_ENV_FILE"
export GITHUB_PATH="$EAGLE_PATH_FILE"
: >"$EAGLE_ENV_FILE"
: >"$EAGLE_PATH_FILE"

steps/00-environment.sh
# shellcheck disable=SC1090
source "$EAGLE_ENV_FILE"

DEPOT_TOOLS_DIR="$BUILDER_ROOT/depot_tools"
if [[ ! -d "$DEPOT_TOOLS_DIR/.git" ]]; then
  git -c core.autocrlf=false clone --no-checkout \
    https://chromium.googlesource.com/chromium/tools/depot_tools.git \
    "$DEPOT_TOOLS_DIR"
fi
git -C "$DEPOT_TOOLS_DIR" config core.autocrlf false
git -C "$DEPOT_TOOLS_DIR" fetch origin "$DEPOT_TOOLS_REVISION"
git -C "$DEPOT_TOOLS_DIR" checkout --detach "$DEPOT_TOOLS_REVISION"

if [[ "$TARGET_OS" == "win" ]]; then
  git -C "$DEPOT_TOOLS_DIR" apply --check "$DEPOT_TOOLS_WINDOWS_PATCH"
  git -C "$DEPOT_TOOLS_DIR" apply "$DEPOT_TOOLS_WINDOWS_PATCH"
  python --version
  python -c 'import sys; assert sys.version_info[:2] == (3, 11)'
  printf '%s\n' '#!/usr/bin/env bash' 'exec python "$@"' > \
    "$DEPOT_TOOLS_DIR/python-bin/python3"
  printf '%s\r\n' '@echo off' 'python %*' > \
    "$DEPOT_TOOLS_DIR/python-bin/python3.bat"
  chmod +x "$DEPOT_TOOLS_DIR/python-bin/python3"
else
  "$DEPOT_TOOLS_DIR/ensure_bootstrap"
fi

if [[ "$TARGET_OS" == "mac" ]]; then
  echo "$DEPOT_TOOLS_DIR" >>"$EAGLE_PATH_FILE"

  XCODE_DEVELOPER_DIR="$(xcode-select -p)"
  if [[ ! -d "$XCODE_DEVELOPER_DIR" ]]; then
    echo "xcode-select returned a missing developer directory: $XCODE_DEVELOPER_DIR" >&2
    exit 1
  fi
  xcodebuild -version
else
  steps/01-install.sh
fi
PATH="$(tr '\n' ':' <"$EAGLE_PATH_FILE")$PATH"
export PATH

PDFIUM_URL="https://pdfium.googlesource.com/pdfium.git"
CONFIG_ARGS=(--custom-var "checkout_configuration=minimal")
gclient config --unmanaged "$PDFIUM_URL" "${CONFIG_ARGS[@]}"
echo "target_os = [ '$TARGET_OS' ]" >>.gclient
GCLIENT_SYNC_ARGS=(-r "$PDFIUM_REVISION" --no-history --shallow)
if [[ "$TARGET_OS" == "win" ]]; then
  # Keep dependency checkout serialized, and defer hooks until the depot_tools
  # copy from PDFium's DEPS is patched before its first gsutil invocation.
  GCLIENT_SYNC_ARGS+=(--jobs 1 --nohooks)
fi
gclient sync "${GCLIENT_SYNC_ARGS[@]}"

if [[ "$TARGET_OS" == "win" ]]; then
  PDFIUM_DEPOT_TOOLS_DIR="$PDFIUM_SOURCE_DIR/third_party/depot_tools"
  git -C "$PDFIUM_DEPOT_TOOLS_DIR" apply --check \
    "$DEPOT_TOOLS_WINDOWS_PATCH"
  git -C "$PDFIUM_DEPOT_TOOLS_DIR" apply "$DEPOT_TOOLS_WINDOWS_PATCH"
  pushd "$PDFIUM_SOURCE_DIR" >/dev/null
  gclient runhooks
  popd >/dev/null
fi

steps/03-patch.sh
git -C "$PDFium_SOURCE_DIR" apply --check "$CUSTOM_PATCH"
git -C "$PDFium_SOURCE_DIR" apply "$CUSTOM_PATCH"
if [[ "$TARGET_OS" == "linux" ]]; then
  pushd "$PDFium_SOURCE_DIR" >/dev/null
  build/install-build-deps.sh --no-prompt
  gclient runhooks
  build/linux/sysroot_scripts/install-sysroot.py "--arch=$TARGET_CPU"
  popd >/dev/null
else
  steps/04-install-extras.sh
fi
steps/05-configure.sh
steps/06-build.sh

if [[ "$TARGET_OS:$TARGET_CPU" == "linux:x64" ]]; then
  ninja -C "$PDFium_BUILD_DIR" pdfium_unittests
  "$PDFium_BUILD_DIR/pdfium_unittests" \
    --gtest_filter='FlateModule.DecodeWithSizeLimit:PDFCatalogTest.GetCustomStream'
fi

steps/07-stage.sh
steps/08-licenses.sh
steps/09-test.sh
steps/10-pack.sh

case "$TARGET_OS" in
  linux)
    nm -D staging/lib/libpdfium.so | grep -F 'FPDFCatalog_GetCustomStream' >/dev/null
    ;;
  mac)
    nm -gU staging/lib/libpdfium.dylib | grep -F 'FPDFCatalog_GetCustomStream' >/dev/null
    ;;
  win)
    LLVM_READOBJ="$PDFium_SOURCE_DIR/third_party/llvm-build/Release+Asserts/bin/llvm-readobj.exe"
    "$LLVM_READOBJ" --coff-exports staging/bin/pdfium.dll | \
      grep -F 'FPDFCatalog_GetCustomStream' >/dev/null
    ;;
esac

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "pdfium-$TARGET_OS-$TARGET_CPU.tgz" > \
    "pdfium-$TARGET_OS-$TARGET_CPU.tgz.sha256"
else
  sha256sum "pdfium-$TARGET_OS-$TARGET_CPU.tgz" > \
    "pdfium-$TARGET_OS-$TARGET_CPU.tgz.sha256"
fi
