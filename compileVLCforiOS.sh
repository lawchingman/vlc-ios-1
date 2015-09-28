#!/bin/sh
# Copyright (C) Pierre d'Herbemont, 2010
# Copyright (C) Felix Paul Kühne, 2012-2015

set -e

SDK=`xcrun --sdk iphoneos --show-sdk-version`
SDK_MIN=7.0
VERBOSE=no
CONFIGURATION="Release"
NONETWORK=no
SKIPLIBVLCCOMPILATION=no
TVOS=no

TESTEDVLCKITHASH=33dc257f
TESTEDMEDIALIBRARYKITHASH=e5ca039f

usage()
{
cat << EOF
usage: $0 [-v] [-k sdk] [-d] [-n] [-l] [-t]

OPTIONS
   -k       Specify which sdk to use (see 'xcodebuild -showsdks', current: ${SDK})
   -v       Be more verbose
   -d       Enable Debug
   -n       Skip script steps requiring network interaction
   -l       Skip libvlc compilation
   -t       Build for TV
EOF
}

spushd()
{
     pushd "$1" 2>&1> /dev/null
}

spopd()
{
     popd 2>&1> /dev/null
}

info()
{
     local green="\033[1;32m"
     local normal="\033[0m"
     echo "[${green}info${normal}] $1"
}

buildxcworkspace()
{
    local target="$2"
    if [ "x$target" = "x" ]; then
    target="$1"
    fi

    info "Building the workspace $1 ($target, ${CONFIGURATION})"

    local architectures=""
    architectures="armv7 armv7s arm64"

    xcodebuild -workspace "$1.xcworkspace" \
    -scheme "Pods-vlc-ios" \
    -sdk iphoneos$SDK \
    -configuration ${CONFIGURATION} \
    ARCHS="${architectures}" \
    IPHONEOS_DEPLOYMENT_TARGET=${SDK_MIN} > ${out}
}

while getopts "hvsdtnluk:" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         v)
             VERBOSE=yes
             ;;
         d)  CONFIGURATION="Debug"
             ;;
         n)
             NONETWORK=yes
             ;;
         l)
             SKIPLIBVLCCOMPILATION=yes
             ;;
         k)
             SDK=$OPTARG
             ;;
         t)
             TVOS=yes
             SDK=`xcrun --sdk appletvos --show-sdk-version`
             SDK_MIN=9.0
             ;;
         ?)
             usage
             exit 1
             ;;
     esac
done
shift $(($OPTIND - 1))

out="/dev/null"
if [ "$VERBOSE" = "yes" ]; then
   out="/dev/stdout"
fi

if [ "x$1" != "x" ]; then
    usage
    exit 1
fi

info "Preparing build dirs"

mkdir -p ImportedSources

spushd ImportedSources

if [ "$NONETWORK" != "yes" ]; then
if ! [ -e MediaLibraryKit ]; then
git clone http://code.videolan.org/videolan/MediaLibraryKit.git
cd MediaLibraryKit
# git reset --hard ${TESTEDMEDIALIBRARYKITHASH}
cd ..
else
cd MediaLibraryKit
git pull --rebase
# git reset --hard ${TESTEDMEDIALIBRARYKITHASH}
cd ..
fi
if ! [ -e VLCKit ]; then
git clone http://code.videolan.org/videolan/VLCKit.git
cd VLCKit
# git reset --hard ${TESTEDVLCKITHASH}
cd ..
else
cd VLCKit
git pull --rebase
# git reset --hard ${TESTEDVLCKITHASH}
cd ..
fi
if ! [ -e GDrive ]; then
svn checkout http://google-api-objectivec-client.googlecode.com/svn/trunk/Source GDrive
cd GDrive
patch -p0 < ../../patches/gdrive/fix-target.patch
patch -p0 < ../../patches/gdrive/session-fetcher-top.diff
cd ..
cd GDrive/HTTPFetcher && patch -p0 < ../../../patches/gdrive/httpfetcher-compilation-fix.diff && cd ../..
cd GDrive/Objects && patch -p0 < ../../../patches/gdrive/session-fetcher-objects.diff && cd ../..
else
cd GDrive && svn up && cd ..
fi
if ! [ -e LXReorderableCollectionViewFlowLayout ]; then
git clone git://github.com/fkuehne/LXReorderableCollectionViewFlowLayout.git
else
cd LXReorderableCollectionViewFlowLayout && git pull --rebase && cd ..
fi
if ! [ -e WhiteRaccoon ]; then
git clone git://github.com/fkuehne/WhiteRaccoon.git
else
cd WhiteRaccoon && git pull --rebase && cd ..
fi
if ! [ -e CocoaHTTPServer ]; then
git clone git://github.com/fkuehne/CocoaHTTPServer.git
else
cd CocoaHTTPServer && git pull --rebase && cd ..
fi
if ! [ -e Dropbox ]; then
DROPBOXSDKVERSION=1.3.13
curl -L -O https://www.dropbox.com/static/developers/dropbox-ios-sdk-${DROPBOXSDKVERSION}.zip
unzip -q dropbox-ios-sdk-${DROPBOXSDKVERSION}.zip
mv dropbox-ios-sdk-${DROPBOXSDKVERSION} Dropbox
rm dropbox-ios-sdk-${DROPBOXSDKVERSION}.zip
rm -rf __MACOSX
fi
if ! [ -e OneDrive ]; then
git clone git://github.com/liveservices/LiveSDK-for-iOS.git OneDrive
cd OneDrive && git am ../../patches/onedrive/*.patch && cd ..
else
cd OneDrive && git pull --rebase && cd ..
fi
fi

spopd #ImportedSources

#
# Build time
#

info "Building"

spushd ImportedSources

spushd VLCKit
echo `pwd`
args=""
if [ "$VERBOSE" = "yes" ]; then
    args="${args} -v"
fi
if [ "$NONETWORK" = "yes" ]; then
    args="${args} -n"
fi
if [ "$SKIPLIBVLCCOMPILATION" = "yes" ]; then
    args="${args} -l"
fi
if [ "$TVOS" = "yes" ]; then
    args="${args} -t"
fi
./buildMobileVLCKit.sh ${args} -k "${SDK}"
spopd

spopd # ImportedSources

#install pods
info "installing pods"
pod install

# Build the VLC for iOS workspace now
if [ "$TVOS" = "no" ]; then
    buildxcworkspace "VLC for iOS" "VLC for iOS"
fi


info "Build completed"
