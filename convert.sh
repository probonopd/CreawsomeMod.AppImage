#! /bin/bash

set -xe

# if this is a tag build, we can use the tag name as the version
if [ "$TRAVIS_TAG" != "" ]; then
    export VERSION="$TRAVIS_TAG"
fi

# if $VERSION is set, build AppImage for that specific version, otherwise use latest version
if (grep -q "BETA" <<< "$VERSION"); then
    URL="https://download.ultimaker.com/Cura_open_beta/Cura-${VERSION}.AppImage"
else
    URLS=$(wget -q https://api.github.com/repos/Ultimaker/Cura/releases -O - | grep AppImage | grep browser_download_url | head -n 1 | cut -d '"' -f 4)
    if [ "$VERSION" == "" ]; then
        URL=$(echo "$URLS" | head -n1)
        export VERSION=$(echo "$URL" | python3 -c "import re, sys; print(re.search('Cura-([\d\.]+)\.AppImage', sys.stdin.read()).group(1))")
    else
        URL=$(echo "$URLS" | grep "$VERSION" | head -n1)
    fi

    if [ "$URL" == "" ]; then
        URL="https://download.ultimaker.com/cura/Ultimaker_Cura-${VERSION}.AppImage"
        curl -I -q "$URL" || URL=""
    fi
fi

if [ "$URL" == "" ]; then
    if [ "$VERSION" != "" ]; then
        echo "Error: could not find URL for user-specified version $VERSION"
    else
        echo "Error: could not determine URL for latest version"
    fi
    exit 1
fi

# use RAM disk if possible
if [ "$CI" == "" ] && [ -d /dev/shm ]; then
    TEMP_BASE=/dev/shm
else
    TEMP_BASE=/tmp
fi

BUILD_DIR=$(mktemp -d -p "$TEMP_BASE" cura-type2-appimages-build-XXXXXX)

cleanup () {
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi
}

trap cleanup EXIT

# store repo root as variable
REPO_ROOT=$(readlink -f $(dirname "$0"))
OLD_CWD=$(readlink -f .)

pushd "$BUILD_DIR"

wget -q -c "$URL"

# ensure consistent filename
filename=$(ls -1 *Cura*.AppImage | head -n1)
if echo "$filename" | grep -q '^Ultimaker_'; then
    new_filename=$(echo "$filename" | cut -d_ -f2-)
    mv "$filename" "$new_filename"
    filename="$new_filename"
fi

MAGIC=$( xxd -p -l 11 "$filename" | tail -c8)
if [ "$MAGIC" == "0414902" ] ; then
  # Type 2 image
  chmod +x "$filename" && ./"$filename" --appimage-extract
else
  # Assume type 1 image
  xorriso -indev "$filename" -osirrox on -extract / squashfs-root
fi

# Rename the application
find squashfs-root -name '*.desktop' -exec sed -i -e 's|^Name=.*|Name=CreawsomeMod|g' {} \;

# Replace the resources
find squashfs-root -name 'resources'
DLD=$(wget -q "https://github.com/trouch/CreawsomeMod/releases" -O - | grep -e "CreawsomeMod-.*zip" | head -n 1 | cut -d '"' -f 2)
wget -q -c "https://github.com/$DLD"
unzip -q -o CreawsomeMod-*.zip
rm -rf squashfs-root/usr/bin/resources
mv ./resources ./squashfs-root/usr/bin/resources
rm -rf CreawsomeMod-*.zip __MACOSX || true

# Make it use .local/share/creawseomemod instead of .local/share/cura
# so that settings do not get mixed up
TARGETDIR=$(readlink -f ./squashfs-root/usr/bin/lib/python*)
wget https://raw.githubusercontent.com/Ultimaker/Cura/$VERSION/cura/CuraApplication.py -O $TARGETDIR/cura/CuraApplication.py
sed -i -e 's|name = "cura"|name = "creawseomemod"|g' $TARGETDIR/cura/CuraApplication.py || true
wget https://raw.githubusercontent.com/Ultimaker/Cura/$VERSION/cura/CuraVersion.py -O $TARGETDIR/cura/CuraVersion.py
sed -i -e 's|\'cura\'|\'creawseomemod\'|g' $TARGETDIR/cura/CuraVersion.py || true

# Remove all but creawsome_ profiles and variants
mv squashfs-root/usr/bin/resources/definitions/fdmprinter.def.json squashfs-root/usr/bin/resources/definitions/creawsome_*.def.json .
rm squashfs-root/usr/bin/resources/definitions/*
mv creawsome_*.def.json squashfs-root/usr/bin/resources/definitions/
mv squashfs-root/usr/bin/resources/variants/creawsome_*.cfg .
rm squashfs-root/usr/bin/resources/variants/*
mv creawsome_*.cfg squashfs-root/usr/bin/resources/variants/

MODVER=$(echo $DLD | cut -d '/' -f 6)
export VERSION=$VERSION.mod$MODVER

# must clean up before building new AppImage so that we won't accidentally move it to $OLD_CWD like the real AppImage
rm "$filename"

wget -c https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage

./appimagetool-x86_64.AppImage -g squashfs-root

mv CreawsomeMod*.AppImage* "$OLD_CWD" # .travis.yml picks it up from there
