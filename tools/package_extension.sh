#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")/.."

# This option enables extra consistency checks and generates extra files (sites.txt and those under build/)
# The resulting extension builds are identical, so there's little reason to use this if you're not a maintainer
RELEASE=
if [ "$1" == "release" ]; then
    RELEASE=1
fi

get_userscript_version() {
    cat $1 | grep '@version *[0-9.]* *$' | sed 's/.*@version *\([0-9.]*\) *$/\1/g'
}

USERVERSION=`get_userscript_version userscript.user.js`
MANIFESTVERSION=`cat manifest.json | grep '"version": *"[0-9.]*", *$' | sed 's/.*"version": *"\([0-9.]*\)", *$/\1/g'`

if [ -z "$USERVERSION" -o -z "$MANIFESTVERSION" ]; then
    echo Broken version regex
    exit 1
fi

if [ "$USERVERSION" != "$MANIFESTVERSION" ]; then
    echo 'Conflicting versions (userscript and manifest)'
    exit 1
fi

if [ -f ./tools/remcomments.js ]; then
    echo "Generating userscript_smaller.user.js"
    node ./tools/remcomments.js userscript.user.js nowatch
else
    echo "Warning: remcomments.js not available, skipping generating userscript_smaller.user.js"
fi

if [ ! -z $RELEASE ]; then
    if [ -f ./tools/gen_minified.js ]; then
        node ./tools/gen_minified.js
        MINVERSION=`get_userscript_version userscript_min.user.js`

        if [ "$MINVERSION" != "$USERVERSION" ]; then
            echo 'Conflicting versions (userscript and minified)'
            exit 1
        fi
    else
        echo "Warning: gen_minified.js not available, skipping OpenUserJS minified version of the userscript"
    fi
fi

if [ ! -z $RELEASE ] && [ -f ./build/userscript_extr.user.js ]; then
    grep '// imu:require_rules' ./build/userscript_extr.user.js 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        echo 'require_rules present in extr.user.js (commit build/rules.js)'
        exit 1
    fi
else
    echo "Warning: userscript_extr.user.js not available"
fi

if [ ! -z $RELEASE ] && [ -d site ]; then
    echo "Updating website files"
    cp site/style.css extension/options.css
    cp userscript_smaller.user.js site/
else
    echo "Warning: website is not available, skipping website build"
fi

echo
echo Creating extension readme file

cat << EOF > EXTENSION_README.txt
3rd-party libraries are machine-generated.
To build them, run ./lib/build_libs.sh

The userscript has the following changes applied:
  * All comments within bigimage() have been removed (comments are nearly always test cases, and currently comprise ~2MB of the userscript's size)
  * It removes useless rules, such as: if (false && ...
  * It removes pieces of code only used for development, marked by imu:begin_exclude and imu:end_exclude
  * Debug calls (nir_debug) are modified to only run when debugging is enabled (which requires editing the source code). This is for performance.
  * common_functions.multidomain__* functions are inlined for performance
  * Unneeded strings within the strings object have been removed

This version is identical to the version offered on Greasyfork (or userscript_smaller.user.js in the Github repository).

This is generated by: node ./tools/remcomments.js userscript.user.js nowatch

To build the extension, run: ./package_extension.sh
  * This also runs the remcomments command above.

Below are the versions of the programs used to generate this extension:

---

EOF

separator() {
    echo >> "$1"
    echo "---" >> "$1"
    echo >> "$1"
}

unzip -v >> EXTENSION_README.txt
separator EXTENSION_README.txt
zip -v >> EXTENSION_README.txt
separator EXTENSION_README.txt
dos2unix --version >> EXTENSION_README.txt
separator EXTENSION_README.txt
unix2dos --version >> EXTENSION_README.txt
separator EXTENSION_README.txt
wget --version >> EXTENSION_README.txt
separator EXTENSION_README.txt
patch --version >> EXTENSION_README.txt
separator EXTENSION_README.txt
sed --version >> EXTENSION_README.txt
separator EXTENSION_README.txt
echo -n "Node.js " >> EXTENSION_README.txt
node --version >> EXTENSION_README.txt
separator EXTENSION_README.txt

echo
echo Building Firefox extension

BASEFILES="LICENSE.txt manifest.json userscript.user.js lib/testcookie_slowaes.js lib/cryptojs_aes.js lib/shaka.debug.js lib/ffmpeg.js lib/stream_parser.js resources/logo_40.png resources/logo_48.png resources/logo_96.png resources/disabled_40.png resources/disabled_48.png resources/disabled_96.png extension/background.js extension/options.css extension/options.html extension/popup.js extension/popup.html"
SOURCEFILES="lib/aes1.patch lib/shim.js lib/fetch_shim.js lib/build_libs.sh EXTENSION_README.txt tools/package_extension.sh tools/remcomments.js tools/util.js"
DIRS="extension lib resources tools"

zip_tempcreate() {
    mkdir tempzip

    for dir in $DIRS; do
        mkdir tempzip/$dir
    done

    for file in $BASEFILES $SOURCEFILES; do
        sourcefile="$file"
        if [ "$file" == "userscript.user.js" ]; then
            sourcefile=userscript_smaller.user.js
        fi

        cp "$sourcefile" tempzip/"$file"
    done
}

zip_tempcreate

zipcmd() {
    echo
    echo "Building extension package: $1"
    echo

    cd tempzip
    zip -r ../"$1" $BASEFILES -x "*~"
    cd ..
}

zipsourcecmd() {
    echo
    echo "Building source package: $1"
    echo

    cd tempzip
    zip -r ../"$1" $BASEFILES $SOURCEFILES -x "*~"
    cd ..
}

rm extension.xpi
zipcmd extension.xpi

getzipfiles() {
    unzip -l "$1" | awk '{print $4}' | awk 'BEGIN{x=0;y=0} /^----$/{x=1} {if (x==1) {x=2} else if (x==2) {print}}' | sed '/^ *$/d' | sort
}

FILES=$(getzipfiles extension.xpi)
echo "$FILES" > files.txt

cat <<EOF > files1.txt
extension/background.js
extension/options.css
extension/options.html
extension/popup.html
extension/popup.js
#-EXTENSION_README.txt
#-lib/aes1.patch
#-lib/build_libs.sh
lib/cryptojs_aes.js
#-lib/fetch_shim.js
lib/ffmpeg.js
lib/shaka.debug.js
lib/stream_parser.js
#-lib/shim.js
lib/testcookie_slowaes.js
LICENSE.txt
manifest.json
resources/disabled_40.png
resources/disabled_48.png
resources/disabled_96.png
resources/logo_40.png
resources/logo_48.png
resources/logo_96.png
#-tools/package_extension.sh
#-tools/remcomments.js
#-tools/util.js
userscript.user.js
EOF

sed 's/^#-//g' files1.txt > files1_source.txt
sed -i '/^#-/d' files1.txt

diffzipfiles() {
    cat $1 $2 | sort | uniq -u
}

DIFF="$(diffzipfiles files.txt files1.txt)"
if [ ! -z "$DIFF" ]; then
    echo
    echo 'Wrong files for firefox extension'
    exit 1
fi

rm -rf tempzip
zip_tempcreate
cp userscript.user.js tempzip/userscript.user.js

rm extension_source.zip
zipsourcecmd extension_source.zip

FILES=$(getzipfiles extension_source.zip)
echo "$FILES" > files.txt

DIFF="$(diffzipfiles files.txt files1_source.txt)"
if [ ! -z "$DIFF" ]; then
    echo
    echo 'Wrong files for source package'
    exit 1
fi

rm files.txt
rm files1.txt
rm files1_source.txt

rm -rf tempzip

if [ -f ./maxurl.pem ]; then
    echo
    echo Building chrome extension
    # This is based on http://web.archive.org/web/20180114090616/https://developer.chrome.com/extensions/crx#scripts

    name=maxurl
    crx="$name.crx"
    pub="$name.pub"
    sig="$name.sig"
    zip="$name.zip"
    key="$name.pem"

    rm $zip $pub $sig

    zip_tempcreate
    zipcmd $zip
    rm -rf tempzip

    # signature
    openssl sha1 -sha1 -binary -sign "$key" < "$zip" > "$sig"

    # public key
    openssl rsa -pubout -outform DER < "$key" > "$pub" 2>/dev/null

    byte_swap () {
    # Take "abcdefgh" and return it as "ghefcdab"
    echo "${1:6:2}${1:4:2}${1:2:2}${1:0:2}"
    }

    crmagic_hex="4372 3234" # Cr24
    version_hex="0200 0000" # 2
    pub_len_hex=$(byte_swap $(printf '%08x\n' $(ls -l "$pub" | awk '{print $5}')))
    sig_len_hex=$(byte_swap $(printf '%08x\n' $(ls -l "$sig" | awk '{print $5}')))
    (
    echo "$crmagic_hex $version_hex $pub_len_hex $sig_len_hex" | xxd -r -p
    cat "$pub" "$sig" "$zip"
    ) > "$crx"
else
    echo "Warning: skipping chrome extension build"
fi

if [ ! -z $RELEASE ]; then
    echo
    echo "Release checklist:"
    echo
    echo ' * Ensure translation strings are updated'
    echo ' * Ensure xx00+ count is updated (userscript - greasyfork/oujs, reddit post, mozilla/opera, website)'
    echo ' * Ensure CHANGELOG.txt is updated'
    echo ' * git add userscript.user.js userscript_smaller.user.js userscript.meta.js CHANGELOG.txt build/userscript_extr.user.js manifest.json sites.txt'
    echo ' * git commit ('$USERVERSION')'
    echo ' * Update greasyfork, oujs, firefox, opera, changelog.txt'
    echo ' * git tag v'$USERVERSION
    echo ' * Update userscript.user.js for site (but check about.js for site count before)'
    echo ' * Update Discord changelog'
else
    echo
    echo "Non-maintainer build finished"
fi
