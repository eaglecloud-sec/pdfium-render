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
CUSTOM_PATCH="$WRAPPER_ROOT/pdfium/patches/eagle_catalog_custom_stream.patch"

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

EAGLE_ENV_FILE="$BUILDER_ROOT/.eagle-env-$TARGET_OS-$TARGET_CPU"
EAGLE_PATH_FILE="$BUILDER_ROOT/.eagle-path-$TARGET_OS-$TARGET_CPU"
export GITHUB_ENV="$EAGLE_ENV_FILE"
export GITHUB_PATH="$EAGLE_PATH_FILE"
: >"$EAGLE_ENV_FILE"
: >"$EAGLE_PATH_FILE"

steps/00-environment.sh
# shellcheck disable=SC1090
source "$EAGLE_ENV_FILE"
steps/01-install.sh
PATH="$(tr '\n' ':' <"$EAGLE_PATH_FILE")$PATH"
export PATH

PDFIUM_URL="https://pdfium.googlesource.com/pdfium.git"
CONFIG_ARGS=(--custom-var "checkout_configuration=minimal")
gclient config --unmanaged "$PDFIUM_URL" "${CONFIG_ARGS[@]}"
echo "target_os = [ '$TARGET_OS' ]" >>.gclient
gclient sync -r "$PDFIUM_REVISION" --no-history --shallow

steps/03-patch.sh
git -C "$PDFium_SOURCE_DIR" apply --check "$CUSTOM_PATCH"
git -C "$PDFium_SOURCE_DIR" apply "$CUSTOM_PATCH"
steps/04-install-extras.sh
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
    nm -D staging/lib/libpdfium.so | grep -q 'FPDFCatalog_GetCustomStream'
    ;;
  mac)
    nm -gU staging/lib/libpdfium.dylib | grep -q 'FPDFCatalog_GetCustomStream'
    ;;
  win)
    LLVM_READOBJ="$PDFium_SOURCE_DIR/third_party/llvm-build/Release+Asserts/bin/llvm-readobj.exe"
    "$LLVM_READOBJ" --coff-exports staging/bin/pdfium.dll | \
      grep -q 'FPDFCatalog_GetCustomStream'
    ;;
esac

shasum -a 256 "pdfium-$TARGET_OS-$TARGET_CPU.tgz" > \
  "pdfium-$TARGET_OS-$TARGET_CPU.tgz.sha256"
