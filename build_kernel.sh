#!/usr/bin/env bash

NUM_OF_CORES=8
TARGET_DIR=$(pwd)
KERNEL_CONFIG_FILE=""
KERNEL_PATCH_FILE=""
KERNEL_CONFIG_FRAG=""
UNAME_ARCH=$(uname -m)
case "$UNAME_ARCH" in
x86_64 | amd64) UNAME_ARCH="x86_64" ;;
aarch64 | arm64) UNAME_ARCH="arm64" ;;
armv7l | armv6l) UNAME_ARCH="arm" ;;
riscv64) UNAME_ARCH="riscv" ;;
mips64* | mips*) UNAME_ARCH="mips" ;;
ppc64le | powerpc64le) UNAME_ARCH="powerpc" ;;
s390x) UNAME_ARCH="s390" ;;
*) echo "unsupported host archticture" >&2 && exit 1 ;;
esac
KERNEL_ARCH=$UNAME_ARCH # TODO: default to be host archticture
KERNEL_TYPE="linux"
DEFAULT_LINUX_VERSION="6.12.y"

usage() {
  echo "Usage: $0 [-v version] [-c config] [-d dir] [-j cores] [-p patch] [-f fragment] [-a archticture] [-t kernel_type]"
  echo "Options:"
  echo "  -v kernel version       Specify a kernel version (default: $DEFAULT_LINUX_VERSION for linux and android-mainline for android)"
  echo "  -c kernel config file   Specify a kernel config file (default: $KERNEL_CONFIG_FILE)"
  echo "  -d directory            Specify a target directory (default: current directory)"
  echo "  -j number of cores      Specify the number of cores (default: $NUM_OF_CORES)"
  echo "  -p patch file           Specify the patch file to apply to the kernel source (default: $KERNEL_PATCH_FILE)"
  echo "  -f fragment config      Specify the config file to merge with the default config (default: $KERNEL_CONFIG_FRAG)"
  echo "  -a archticture          Specify a target archticture in which the kernel will be compiled to (default: $KERNEL_ARCH)."
  echo "  -t kernel type          Specify to build android kernels instead (default: $KERNEL_TYPE)"
  exit 1
}

while getopts ":v:d:c:j:p:f:a:t:" opt; do
  case $opt in
  v)
    SRC_KERNEL_VERSION="$OPTARG"
    ;;
  d)
    TARGET_DIR="$OPTARG"
    if [[ "$TARGET_DIR" != /* ]]; then
      TARGET_DIR="$(pwd)/$TARGET_DIR"
    fi
    ;;
  c)
    KERNEL_CONFIG_FILE="$OPTARG"
    if [[ "$KERNEL_CONFIG_FILE" != /* ]]; then
      KERNEL_CONFIG_FILE="$(pwd)/$KERNEL_CONFIG_FILE"
    fi
    ;;
  j)
    NUM_OF_CORES="$OPTARG"
    ;;
  p)
    KERNEL_PATCH_FILE="$OPTARG"
    if [[ "$KERNEL_PATCH_FILE" != /* ]]; then
      KERNEL_PATCH_FILE="$(pwd)/$KERNEL_PATCH_FILE"
    fi
    ;;
  f)
    KERNEL_CONFIG_FRAG="$OPTARG"
    if [[ "$KERNEL_CONFIG_FRAG" != /* ]]; then
      KERNEL_CONFIG_FRAG="$(pwd)/$KERNEL_CONFIG_FRAG"
    fi
    ;;
  a)
    KERNEL_ARCH="$OPTARG"
    valid_archs=(arm arm64 mips powerpc riscv s390 x86_64 i386)
    if [[ " ${valid_archs[*]} " != *" $value "* ]]; then
      echo "Invalid archticture $KERNEL_ARCH" >&2
      exit 1
    fi
    ;;
  t)
    KERNEL_TYPE="$OPTARG"
    if [[ "$KERNEL_TYPE" != "linux" ]] && [[ "$KERNEL_TYPE" != "android" ]]; then
      echo "Invalid kernel type $KERNEL_TYPE" >&2
      exit 1
    fi
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    usage
    ;;
  :)
    echo "Option -$OPTARG requires an argument." >&2
    usage
    ;;
  esac
done

if [[ "$UNAME_ARCH" != "$KERNEL_ARCH" ]]; then
  case "$KERNEL_ARCH" in
  arm64) CROSS=aarch64-linux-gnu- ;;
  arm) CROSS=arm-linux-gnueabihf- ;;
  riscv) CROSS=riscv64-linux-gnu- ;;
  mips) CROSS=mipsel-linux-gnu- ;;
  powerpc) CROSS=powerpc64le-linux-gnu- ;;
  s390) CROSS=s390x-linux-gnu- ;;
  x86_64 | i386) CROSS=x86_64-linux-gnu- ;;
  *) CROSS="" ;;
  esac
  export ARCH=$KERNEL_ARCH
  export CROSS_COMPILE=$CROSS
fi

if [[ "$KERNEL_TYPE" == "linux" ]]; then
  if [ -z "$SRC_KERNEL_VERSION" ]; then
    SRC_KERNEL_VERSION=$DEFAULT_LINUX_VERSION
  fi
  ROOT_URL="https://cdn.kernel.org/pub/linux/kernel/v$(echo $SRC_KERNEL_VERSION | cut -d"." -f1).x"
  if [[ "$SRC_KERNEL_VERSION" == *.y ]]; then
    SRC_KERNEL_VERSION=$(curl -s $ROOT_URL/ | grep -oE "${SRC_KERNEL_VERSION::-1}[0-9]+" | sort -r -V | head -n1)
  fi
  SRC_DIR_NAME="linux-$SRC_KERNEL_VERSION"
  COMPRESSED_SRC="$SRC_DIR_NAME.tar.xz"
else
  if [ -z "$SRC_KERNEL_VERSION" ]; then
    SRC_KERNEL_VERSION="android-mainline"
  fi
  ROOT_URL="https://android.googlesource.com/kernel/common/+archive/refs/heads"
  SRC_DIR_NAME="$SRC_KERNEL_VERSION"
  COMPRESSED_SRC="$SRC_DIR_NAME.tar.gz"
fi

echo "building $KERNEL_TYPE kernel version $SRC_KERNEL_VERSION to directory $TARGET_DIR with $NUM_OF_CORES cores"
mkdir -p $TARGET_DIR
cd $TARGET_DIR
echo "downloading and extracting $SRC_DIR_NAME ..."
wget -q $ROOT_URL/$COMPRESSED_SRC -O ./$COMPRESSED_SRC
if [ $? -ne 0 ]; then
  echo "wget failed on getting the $KERNEL_TYPE kernel src code (url = $ROOT_URL/$COMPRESSED_SRC), exiting..."
  exit 1
fi
if [[ "$KERNEL_TYPE" == "linux" ]]; then
  tar -xf ./$COMPRESSED_SRC
else
  mkdir -p ./$SRC_DIR_NAME
  tar -xf ./$COMPRESSED_SRC -C ./$SRC_DIR_NAME
fi
rm ./$COMPRESSED_SRC

if [ ! -z "$KERNEL_PATCH_FILE" ] && [ -f "$KERNEL_PATCH_FILE" ]; then
  cd ./$SRC_DIR_NAME
  cp $KERNEL_PATCH_FILE ./
  patch -p2 <./$(basename "$KERNEL_PATCH_FILE")
  if [ $? -ne 0 ]; then
    echo "failed to apply patch"
    exit 1
  fi
  cd -
fi

cd ./$SRC_DIR_NAME
if [ -z "$KERNEL_CONFIG_FILE" ] || [ ! -f "$KERNEL_CONFIG_FILE" ]; then
  echo "config file is not specified or invalid"
  echo "configuing the $SRC_DIR_NAME kernel..."
  make -s defconfig
  KERNEL_CONFIG_FILE=$(pwd)/.config
else
  cp $KERNEL_CONFIG_FILE .config
fi
if [ "$KERNEL_CONFIG_FRAG" ] && [ -f "$KERNEL_CONFIG_FRAG" ]; then
  ./scripts/kconfig/merge_config.sh .config $KERNEL_CONFIG_FRAG
  make olddefconfig
elif [ -z "$KERNEL_CONFIG_FILE" ] || [ ! -f "$KERNEL_CONFIG_FILE" ]; then
  make -s menuconfig
fi

echo "building $SRC_DIR_NAME kernel..."
make -s -j $NUM_OF_CORES

if [ $? -ne 0 ]; then
  echo "failed building the kernel, exiting..."
  exit 1
fi
echo "finished building!!"
pwd
