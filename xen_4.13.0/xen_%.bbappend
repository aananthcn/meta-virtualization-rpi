HOMEPAGE = "http://xen.org"
LICENSE = "GPLv2"
SECTION = "console/tools"

inherit autotools-brokensep

#require xen-arch.inc

PACKAGECONFIG ??= " \
    sdl \
    ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'systemd', '', d)} \
    ${@bb.utils.contains('XEN_TARGET_ARCH', 'x86_64', 'hvm', '', d)} \
    "

PACKAGECONFIG[sdl] = "--enable-sdl,--disable-sdl,virtual/libsdl,"
PACKAGECONFIG[xsm] = "--enable-xsmpolicy,--disable-xsmpolicy,checkpolicy-native,"
PACKAGECONFIG[systemd] = "--enable-systemd,--disable-systemd,systemd,"
PACKAGECONFIG[hvm] = "--with-system-seabios="/usr/share/firmware/bios.bin",--disable-seabios,seabios ipxe vgabios,"
PACKAGECONFIG[externalblktap] = ",,,"

DEPENDS = " \
    ${@bb.utils.contains('XEN_TARGET_ARCH', 'x86_64', 'dev86-native', '', d)} \
    bison-native \
    flex-native \
    file-native \
    gettext-native \
    acpica-native \
    ncurses-native \
    util-linux-native \
    xz-native \
    bridge-utils \
    curl \
    dtc \
    gettext \
    glib-2.0 \
    gnutls \
    iproute2 \
    libnl \
    ncurses \
    openssl \
    pciutils \
    pixman \
    procps \
    python3 \
    libaio \
    lzo \
    util-linux \
    xz \
    yajl \
    zlib \
    gnu-efi \
    "

#### REQUIRED ENVIRONMENT VARIABLES ####
export BUILD_SYS
export HOST_SYS
export STAGING_INCDIR
export STAGING_LIBDIR

# specify xen hypervisor to build/target
export XEN_TARGET_ARCH = "${@map_xen_arch(d.getVar('TARGET_ARCH'), d)}"
export XEN_COMPILE_ARCH = "${@map_xen_arch(d.getVar('BUILD_ARCH'), d)}"

python () {
    if d.getVar('XEN_TARGET_ARCH') == 'INVALID':
        raise bb.parse.SkipPackage('Cannot map `%s` to a xen architecture' % d.getVar('TARGET_ARCH'))
}

# Yocto appends ${PN} to libexecdir by default and Xen appends 'xen' as well
# the result is a nested xen/xen/ so let's avoid that by shunning Yocto's
# extra ${PN} appended.
libexecdir = "${libdir}"

# hardcoded as Linux, as the only compatible hosts are Linux.
export XEN_OS = "Linux"

# this is used for the header (#!${bindir}/python) of the install python scripts
export PYTHONPATH="${bindir}/env python3"
export ac_cv_path_PYTHONPATH="${bindir}/env python3"
export DISTUTILS_BUILD_ARGS
export DISTUTILS_INSTALL_ARGS

# xen and seabios require HOSTCC and HOSTCXX set to cross-compile
export HOSTCC="${BUILD_CC}"
export HOSTCXX="${BUILD_CXX}"

# make xen requires CROSS_COMPILE set by hand as it does not abide by ./configure
export CROSS_COMPILE="${TARGET_PREFIX}"

# overide LDFLAGS to allow xen to build without: "x86_64-oe-linux-ld: unrecognized option '-Wl,-O1'"
export LDFLAGS=""

# Pass through the Yocto distro compiler flags via the Xen-provided variables.
# Special handling:
# - Yocto supplies the _FORTIFY_SOURCE flag via CC/CPP/CXX but then passes the
#   optimization -O via C*FLAGS which is problematic when the CFLAGS are cleared
#   within the build because compilation fails with the compiler stating
#   "_FORTIFY_SOURCE requires compiling with optimization (-O)".
# - Move HOST_CC_ARCH into the Xen-provided CFLAGS variables and keep
#   TOOLCHAIN_OPTIONS set via CC: this enables hvmloader to be built correctly.
#   It must not be compiled with SSE compiler options enabled and the Xen build
#   explicitly clears CFLAGS to ensure that, so such options must not be passed
#   in via the tool variable. hvmloader is required to run HVM-mode guest VMs.
CC="${CCACHE}${HOST_PREFIX}gcc ${TOOLCHAIN_OPTIONS} ${CC_REPRODUCIBLE_OPTIONS}"
EXTRA_CFLAGS_XEN_CORE="${HOST_CC_ARCH} ${CFLAGS}"
EXTRA_CFLAGS_XEN_TOOLS="${HOST_CC_ARCH} ${CFLAGS}"
# 32-bit ARM needs the TUNE_CCARGS component of HOST_CC_ARCH to be passed
# in CC to ensure that configure can compile binaries for the right arch.
CC_arm="${CCACHE}${HOST_PREFIX}gcc ${TUNE_CCARGS} ${TOOLCHAIN_OPTIONS} ${CC_REPRODUCIBLE_OPTIONS}"
EXTRA_CFLAGS_XEN_CORE_arm="${SECURITY_CFLAGS} ${CFLAGS}"
EXTRA_CFLAGS_XEN_TOOLS_arm="${SECURITY_CFLAGS} ${CFLAGS}"

# There are no Xen-provided variables for C++, so append to the tool variables:
CPP_append = " ${CPPFLAGS}"
CXX_append = " ${CXXFLAGS}"

EXTRA_OECONF += " \
    --exec-prefix=${prefix} \
    --prefix=${prefix} \
    --host=${HOST_SYS} \
    --with-systemd=${systemd_unitdir}/system \
    --with-systemd-modules-load=${systemd_unitdir}/modules-load.d \
    --disable-stubdom \
    --disable-ioemu-stubdom \
    --disable-pv-grub \
    --disable-xenstore-stubdom \
    --disable-rombios \
    --disable-ocamltools \
    --with-initddir=${INIT_D_DIR} \
    --with-sysconfig-leaf-dir=default \
    --with-system-qemu=/usr/bin/qemu-system-i386 \
    --disable-qemu-traditional \
    "

EXTRA_OEMAKE += "STDVGA_ROM=${STAGING_DIR_HOST}/usr/share/firmware/vgabios-0.7a.bin"
EXTRA_OEMAKE += "CIRRUSVGA_ROM=${STAGING_DIR_HOST}/usr/share/firmware/vgabios-0.7a.cirrus.bin"
EXTRA_OEMAKE += "SEABIOS_ROM=${STAGING_DIR_HOST}/usr/share/firmware/bios.bin"
EXTRA_OEMAKE += "ETHERBOOT_ROMS=${STAGING_DIR_HOST}/usr/share/firmware/rtl8139.rom"

# prevent the Xen build scripts from fetching things during the build
# all dependencies should be reflected in the Yocto recipe
EXTRA_OEMAKE += "WGET=/bin/false"
EXTRA_OEMAKE += "GIT=/bin/false"

# Improve build reproducibility: provide values for build variables.
def get_build_time_vars(d):
    source_date_epoch = d.getVar('SOURCE_DATE_EPOCH')
    if source_date_epoch is not None:
        import datetime
        utc_datetime = datetime.datetime.utcfromtimestamp(float(source_date_epoch))
        return " XEN_BUILD_DATE=" + utc_datetime.strftime("%Y-%m-%d") + \
               " XEN_BUILD_TIME=" + utc_datetime.strftime("%H:%M:%S")
    return ""
EXTRA_OEMAKE += "${@['', 'XEN_WHOAMI=${PF} XEN_DOMAIN=${DISTRO} XEN_BUILD_HOST=${PN}-buildhost'] \
                    [d.getVar('BUILD_REPRODUCIBLE_BINARIES') == '1']}${@get_build_time_vars(d)}"

# Improve build reproducibility: compiler flags to remove filesystem differences.
CC_REPRODUCIBLE_OPTIONS = "${@['', '-gno-record-gcc-switches ' + \
                                   '-ffile-prefix-map=${S}=${PN}-source ' + \
                                   '-fdebug-prefix-map=${WORKDIR}=${PN}'] \
                             [d.getVar('BUILD_REPRODUCIBLE_BINARIES') == '1']}"

# check for XSM in package config to allow XSM_ENABLE to be set
python () {
    pkgconfig = d.getVar('PACKAGECONFIG')
    if ('xsm') in pkgconfig.split():
        d.setVar('XSM_ENABLED', '1')
    else:
        d.setVar('XSM_ENABLED', '0')
}

do_post_patch() {
    # fixup AS/CC/CCP/etc variable within StdGNU.mk
    for i in LD CC CPP CXX; do
        sed -i "s/^\($i\s\s*\).*=/\1?=/" ${S}/config/StdGNU.mk
    done
    # fixup environment passing in some makefiles
    sed -i 's#\(\w*\)=\(\$.\w*.\)#\1="\2"#' ${S}/tools/firmware/Makefile

    # libsystemd-daemon -> libsystemd for newer systemd versions
    sed -i 's#libsystemd-daemon#libsystemd#' ${S}/tools/configure

    # Improve build reproducibility: disable insertion of the build timestamp
    # into the x86 EFI hypervisor binary.
    # binutils should allow a user-supplied timestamp or use SOURCE_DATE_EPOCH
    # for PE but currently does not.
    if [ "${BUILD_REPRODUCIBLE_BINARIES}" = "1" ] ; then
        sed '/^EFI_LDFLAGS = /{a EFI_LDFLAGS += --no-insert-timestamp
}' -i "${S}/xen/arch/x86/Makefile"
    fi
}

do_post_patch_append_arm()  {
    # The hypervisor binary must not be built with the hard floating point ABI.
    echo "CC := \$(filter-out ${TUNE_CCARGS},\$(CC))" >> ${S}/xen/arch/arm/Rules.mk
}

addtask post_patch after do_patch before do_configure

# Allow all hypervisor settings in a defconfig
EXTRA_OEMAKE += "XEN_CONFIG_EXPERT=y"
# Build release versions always. Technically since we track release
# tarballs this always happens but occasionally people pull in patches
# from staging that reverts this
EXTRA_OEMAKE += "debug=y CONFIG_DEBUG=y CONFIG_EARLY_PRINTK=8250,0xfe215040,2"
EXTRA_OECONF += "CONFIG_EARLY_PRINTK=8250,0xfe215040,2"

do_configure_common() {
    cd ${S}

    #./configure --enable-xsmpolicy does not set XSM_ENABLE must be done manually
    if [ "${XSM_ENABLED}" = "1" ]; then
        echo "XSM_ENABLE := y" > ${S}/.config
    fi

    if [ -f "${WORKDIR}/defconfig" ]; then
        cp "${WORKDIR}/defconfig" "${B}/xen/.config" || \
        bbfatal "Unable to copy defconfig to .config"
    fi

    unset CFLAGS

    # do configure
    oe_runconf EXTRA_CFLAGS_XEN_CORE="${EXTRA_CFLAGS_XEN_CORE}" \
               EXTRA_CFLAGS_XEN_TOOLS="${EXTRA_CFLAGS_XEN_TOOLS}" \
               PYTHON="${PYTHON}"
}

do_compile_prepend() {
    # workaround for build bug when CFLAGS is exported
    # https://www.mail-archive.com/xen-devel@lists.xen.org/msg67822.html
    unset CFLAGS
}

do_install_prepend() {
    # CFLAGS is used to set PY_CFLAGS which affects the pygrub install
    # so also need to unset CFLAGS here:
    unset CFLAGS
}
