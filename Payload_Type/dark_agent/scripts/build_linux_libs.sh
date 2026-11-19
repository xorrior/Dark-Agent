#!/bin/bash
# Builds Linux aarch64 static libraries from source using Zig as the cross-compiler.
# Runs once at Docker image build time. Produces libs under /opt/multiarch-libs/aarch64-linux-gnu/.
#
# Native x86_64 Linux libs are already available via the system package manager and
# the OpenSSL build in the Dockerfile — this script is only needed for cross-compiled
# aarch64 targets.
#
# Requires:
#   - zig in PATH
#   - cmake, wget, tar, make in PATH

set -e

LINUX_TARGET="aarch64-linux-gnu"
LINUX_PREFIX="/opt/multiarch-libs/aarch64-linux-gnu"
JOBS=2

ZIG_CC="zig cc -target ${LINUX_TARGET}"
ZIG_CXX="zig c++ -target ${LINUX_TARGET}"
ZIG_AR="zig ar"
ZIG_RANLIB="zig ranlib"

mkdir -p "${LINUX_PREFIX}/lib/pkgconfig"
mkdir -p "${LINUX_PREFIX}/include"
mkdir -p /tmp/linux-libs-build
cd /tmp/linux-libs-build

# cmake needs single-binary tools — create wrappers for zig subcommands
cat > /tmp/zig-ar << 'ZIGEOF'
#!/bin/sh
zig ar "$@"
ZIGEOF
chmod +x /tmp/zig-ar

cat > /tmp/zig-ranlib << 'ZIGEOF'
#!/bin/sh
zig ranlib "$@"
ZIGEOF
chmod +x /tmp/zig-ranlib

cat > /tmp/zig-cc-linux << ZIGEOF
#!/bin/sh
zig cc -target ${LINUX_TARGET} "\$@"
ZIGEOF
chmod +x /tmp/zig-cc-linux

echo "[*] Building OpenSSL for Linux aarch64..."
OPENSSL_VER=3.1.2
wget -q "https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz"
tar -xzf "openssl-${OPENSSL_VER}.tar.gz"
cd "openssl-${OPENSSL_VER}"
CC="zig cc" \
CFLAGS="-target ${LINUX_TARGET}" \
AR="${ZIG_AR}" \
RANLIB="${ZIG_RANLIB}" \
./Configure linux-aarch64 \
    no-shared \
    no-tests \
    no-ui-console \
    no-async \
    --prefix="${LINUX_PREFIX}" \
    --openssldir="/etc/ssl"
make -j${JOBS} build_libs
make install_dev
cd /tmp/linux-libs-build
echo "[+] OpenSSL done"

echo "[*] Building pcre2 for Linux aarch64..."
PCRE2_VER=10.47
wget -q "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VER}/pcre2-${PCRE2_VER}.tar.gz"
tar -xzf "pcre2-${PCRE2_VER}.tar.gz"
mkdir -p "pcre2-${PCRE2_VER}/build" && cd "pcre2-${PCRE2_VER}/build"
cmake .. \
    -DBUILD_SHARED_LIBS=OFF \
    -DPCRE2_BUILD_TESTS=OFF \
    -DPCRE2_BUILD_PCRE2GREP=OFF \
    -DCMAKE_C_COMPILER="/tmp/zig-cc-linux" \
    -DCMAKE_AR="/tmp/zig-ar" \
    -DCMAKE_RANLIB="/tmp/zig-ranlib" \
    -DCMAKE_INSTALL_PREFIX="${LINUX_PREFIX}" \
    -DCMAKE_SYSTEM_NAME=Linux
make -j${JOBS}
make install
cd /tmp/linux-libs-build
echo "[+] pcre2 done"

echo "[*] Building libevent for Linux aarch64..."
LIBEVENT_VER=2.1.12
wget -q "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VER}-stable/libevent-${LIBEVENT_VER}-stable.tar.gz"
tar -xzf "libevent-${LIBEVENT_VER}-stable.tar.gz"
cd "libevent-${LIBEVENT_VER}-stable"
# HAVE_ARC4RANDOM_BUF: glibc's stdlib.h already declares arc4random_buf,
# which conflicts with libevent's static definition. This tells libevent
# to use the system version instead of defining its own.
CC="${ZIG_CC}" \
CXX="${ZIG_CXX}" \
CFLAGS="-DHAVE_ARC4RANDOM_BUF" \
AR="/tmp/zig-ar" \
RANLIB="/tmp/zig-ranlib" \
./configure \
    --host=aarch64-linux-gnu \
    --disable-shared \
    --enable-static \
    --disable-openssl \
    --disable-samples \
    --disable-libevent-regress \
    --prefix="${LINUX_PREFIX}"
make -j${JOBS}
make install
cd /tmp/linux-libs-build
echo "[+] libevent done"

echo "[*] Building Boehm GC for Linux aarch64..."
BDWGC_VER=8.2.12
ATOMICOPS_VER=7.10.0
wget -q "https://github.com/ivmai/bdwgc/releases/download/v${BDWGC_VER}/gc-${BDWGC_VER}.tar.gz"
wget -q "https://github.com/ivmai/libatomic_ops/releases/download/v${ATOMICOPS_VER}/libatomic_ops-${ATOMICOPS_VER}.tar.gz"
tar -xzf "gc-${BDWGC_VER}.tar.gz"
tar -xzf "libatomic_ops-${ATOMICOPS_VER}.tar.gz"
mv "libatomic_ops-${ATOMICOPS_VER}" "gc-${BDWGC_VER}/libatomic_ops"
mkdir -p "gc-${BDWGC_VER}/build" && cd "gc-${BDWGC_VER}/build"
cmake .. \
    -DBUILD_SHARED_LIBS=OFF \
    -Dbuild_tests=OFF \
    -Denable_docs=OFF \
    -DCMAKE_C_COMPILER="/tmp/zig-cc-linux" \
    -DCMAKE_AR="/tmp/zig-ar" \
    -DCMAKE_RANLIB="/tmp/zig-ranlib" \
    -DCMAKE_INSTALL_PREFIX="${LINUX_PREFIX}" \
    -DCMAKE_SYSTEM_NAME=Linux
make -j${JOBS}
make install
cd /tmp/linux-libs-build
echo "[+] Boehm GC done"

echo "[*] Building zlib for Linux aarch64..."
ZLIB_VER=1.3.1
wget -q "https://github.com/madler/zlib/releases/download/v${ZLIB_VER}/zlib-${ZLIB_VER}.tar.gz"
tar -xzf "zlib-${ZLIB_VER}.tar.gz"
cd "zlib-${ZLIB_VER}"
CC="/tmp/zig-cc-linux" \
AR="/tmp/zig-ar" \
RANLIB="/tmp/zig-ranlib" \
./configure \
    --static \
    --prefix="${LINUX_PREFIX}"
make -j${JOBS} libz.a
make install
cd /tmp/linux-libs-build
echo "[+] zlib done"

rm -rf /tmp/linux-libs-build
echo "[+] All Linux aarch64 static libraries built successfully"
echo "    Installed to: ${LINUX_PREFIX}"
ls "${LINUX_PREFIX}/lib/"*.a
