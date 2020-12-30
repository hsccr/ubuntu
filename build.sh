#!/bin/sh

set -e

CURDIR=$(realpath $(dirname ${0}))
PKGDIR=${CURDIR}
DOCKERDIR=${PKGDIR}/docker
DOCKER_IMAGE_TAG=pkg-dev
DOCKER_ROOT=/git
DOCKER_PKGDIR=${DOCKER_ROOT}/pkg
UBUNTU_VERSIONS="bionic disco focal"

ECHO()
{
  echo "${RED}PKG:${YELLOW} ${1} ..${NORMAL}"
}

build_intel_vaapi_driver()
{
  rm -fr ${PKGDIR}/build/*
  cd ${PKGDIR}/build

  sudo apt --assume-yes build-dep i965-va-driver
  apt --assume-yes source i965-va-driver

  src_dir=$(find -name "intel-vaapi-driver*" -type d)
  if [ -z "$src_dir" ]; then
    ECHO "not found intel-vaapi-driver"
    exit 1
  fi

  cd ${src_dir}
  [ ! -d "debian/patches" ] && mkdir -p debian/patches

  for patch in ${PKGDIR}/packages/libva-intel-driver/*.patch; do
    echo "${patch} debian/patches"
    cp ${patch} debian/patches

    basename=$(basename $patch)
    echo ${basename} >> debian/patches/series
  done

  # apply patches
  quilt push -a

  # update changelog
  dch -b -U -i --distribution stable "build package with patches"

  # build package
  debuild -b -us -uc

  cp ${PKGDIR}/build/*.deb ${PKGDIR}/deb/${UBUNTU_CODENAME}
}

build_intel_media_driver()
{
  rm -fr ${PKGDIR}/build/*
  cd ${PKGDIR}/build

  sudo apt --assume-yes build-dep intel-media-va-driver
  apt --assume-yes source intel-media-va-driver

  src_dir=$(find -name "intel-media-driver*" -type d)
  if [ -z "$src_dir" ]; then
    ECHO "not found intel-media-driver"
    exit 1
  fi

  cd ${src_dir}
  [ ! -d "debian/patches" ] && mkdir -p debian/patches

  for patch in ${PKGDIR}/packages/intel-media-driver/*.patch; do
    echo "${patch} debian/patches"
    cp ${patch} debian/patches

    basename=$(basename $patch)
    echo ${basename} >> debian/patches/series
  done

  # apply patches
  quilt push -a

  # update changelog
  dch -b -U -i --distribution stable "build package with patches"

  # build package
  debuild -b -us -uc

  cp ${PKGDIR}/build/*.deb ${PKGDIR}/deb/${UBUNTU_CODENAME}
}

build_libfprint()
{
  rm -fr ${PKGDIR}/build/*
  cd ${PKGDIR}/build

  # install dependency
  sudo apt --assume-yes install debhelper gtk-doc-tools libglib2.0-doc libnss3-dev libpixman-1-dev libusb-1.0-0-dev libxv-dev

  cp -r ${PKGDIR}/libfprint ${PKGDIR}/build

  # import debian folder for building debian package
  wget https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/libfprint/1:1.0-1/libfprint_1.0-1.debian.tar.xz
  tar -xvf libfprint_1.0-1.debian.tar.xz -C ${PKGDIR}/build/libfprint

  cd ${PKGDIR}/build/libfprint

  # update changelog
  dch -b -U -i --distribution stable "build package"

  # build package
  debuild -b -us -uc

  cp ${PKGDIR}/build/*.deb ${PKGDIR}/deb/${UBUNTU_CODENAME}
}

build_libcurl4()
{
  rm -fr ${PKGDIR}/build/*
  cd ${PKGDIR}/build

  sudo apt --assume-yes build-dep libcurl4
  apt --assume-yes source libcurl4

  src_dir=$(find -name "curl-*" -type d)
  if [ -z "$src_dir" ]; then
    ECHO "not found curl"
    exit 1
  fi

  cd ${src_dir}
  [ ! -d "debian/patches" ] && mkdir -p debian/patches

  for patch in ${PKGDIR}/curl/*.patch; do
    echo "${patch} debian/patches"
    cp ${patch} debian/patches

    basename=$(basename $patch)
    echo ${basename} >> debian/patches/series
  done

  # apply patches
  quilt push -a

  # update changelog
  dch -b -U -i --distribution stable "build package with patches"

  # build package
  debuild -b -us -uc

  cp ${PKGDIR}/build/*.deb ${PKGDIR}/deb/${UBUNTU_CODENAME}
}

packages()
{
  UBUNTU_CODENAME=$(lsb_release -c | awk '{ print $2 }')

  ECHO "build debian package $UBUNTU_CODENAME"

  sudo apt --assume-yes update

  [ ! -d "${PKGDIR}/build" ] && mkdir -p ${PKGDIR}/build

  rm -fr deb/${UBUNTU_CODENAME}
  [ ! -d "${PKGDIR}/deb/${UBUNTU_CODENAME}" ] && mkdir -p ${PKGDIR}/deb/${UBUNTU_CODENAME}

  build_libfprint
  build_intel_vaapi_driver

  case $UBUNTU_CODENAME in
    # Ubuntu 18.04 (bionic)
    "bionic")
      build_libcurl4;;
    # Ubuntu 19.04 (disco)
    # Ubuntu 20.04 (focal)
    "disco" | "focal")
      build_intel_media_driver;;
    *);;
  esac
}

docker_images()
{
  for codename in $UBUNTU_VERSIONS
  do
    ECHO "Build 'Dockerfile-${codename}' docker image"
    docker build -t ${DOCKER_IMAGE_TAG}-${codename} ${DOCKERDIR} \
      -f ${DOCKERDIR}/Dockerfile-${codename} \
      --build-arg USER=$USER \
      --build-arg UID=$(id -u) \
      --build-arg GID=$(id -g) \
      --build-arg DOCKER_ROOT=${DOCKER_ROOT} \
      --build-arg DOCKER_PKGDIR=${DOCKER_PKGDIR}
  done
}

docker_console()
{
  if [ -z "$UBUNTU_CODENAME" ]; then
    UBUNTU_CODENAME="bionic"
  fi

  if [ -z "$DOCKER_USER" ]; then
    DOCKER_USER=$(id -u):$(id -g)
  fi

  ECHO "Run docker console $UBUNTU_CODENAME with $DOCKER_USER"

  docker run --rm -it \
    -u ${DOCKER_USER} \
    -v ${PKGDIR}:${DOCKER_PKGDIR} \
    ${DOCKER_IMAGE_TAG}-${UBUNTU_CODENAME} /bin/bash
}

docker_packages()
{
  for codename in $UBUNTU_VERSIONS
  do
    ECHO "Build debian package in docker '${DOCKER_IMAGE_TAG}-${codename}'"

    # Build package by using docker
    docker run --rm -t \
      -u $(id -u):$(id -g) \
      -v ${PKGDIR}:${DOCKER_PKGDIR} \
      ${DOCKER_IMAGE_TAG}-${codename} /bin/bash -c "cd ${DOCKER_PKGDIR} && ./build.sh packages"
  done
}

help()
{
  PROG=$(basename ${0})
  echo "Usage:"
  echo "  ${YELLOW}${PROG} ${RED}packages        ${NORMAL} # Build debian package"
  echo "  ${YELLOW}${PROG} ${RED}docker_images   ${NORMAL} # Build docker image"
  echo "  ${YELLOW}${PROG} ${RED}docker_console  ${NORMAL} # Run docker console"
  echo "  ${YELLOW}${PROG} ${RED}docker_packages ${NORMAL} # Build debian package in docker"
  exit 1
}

[ $# -eq 0 ] && help

while [ $# -ne 0 ]
do
  hash ${1} &>/dev/null || help
  ${1}
  shift
done

exit 0
