#!/bin/bash
# Boot compiler is the installed ghc74 RPM, placed where the inner script
# looks for a 7.4.2 prefix. The final happy and alex are configured again
# with --prefix=/usr so Paths_* getDataDir is /usr/share/<pkg>-<ver>. The
# inner script's own prefix is a work directory it deletes; it must not be /usr.
set -euo pipefail

ROOT=${1:?usage: ghc74tools-build.sh ROOT LIBDIR}
LIBDIR=${2:?}
export STAGE="$ROOT"
export GMP_PREFIX="$LIBDIR/gmp612"
export DATADIR=/usr/share
export TMPDIR="$ROOT/tmp"
mkdir -p "$TMPDIR"
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS RPM_OPT_FLAGS RPM_LD_FLAGS || true
unset GHC_PACKAGE_PATH || true
ulimit -s unlimited 2>/dev/null || true

fail() { printf 'ghc74tools: %s\n' "$*" >&2; exit 1; }

sha_ok() {
	local file=$1 expect=$2 got
	got=$(sha256sum "$file") || fail "sha256sum $file"
	got=${got%% *}
	[ "$got" = "$expect" ] || fail "sha256 $file is $got want $expect"
}

IN=$ROOT/incoming
[ -d "$IN" ] || fail "missing $IN"
sha_ok "$IN/happy-1.19.5.tar.gz" 62f03ac11d7b4b9913f212f5aa2eee1087f3b46dc07d799d41e1854ff02843da
sha_ok "$IN/alex-3.2.7.4.tar.gz" 8a13fa01ea00883aa3d75d15ce848835b18631b8c9a4966961492d7c6095226f
sha_ok "$IN/ghc-7.4.2-src.tar.bz2" f2ee1289a33cc70539287129841acc7eaf16112bb60c59b5a6ee91887bfd836d
[ -x /usr/bin/ghc74 ] || fail "/usr/bin/ghc74 missing"
[ -x /usr/bin/ghc-pkg74 ] || fail "/usr/bin/ghc-pkg74 missing"
[ -x /usr/bin/happy1195-mhs ] || fail "/usr/bin/happy1195-mhs missing"
[ -f "$DATADIR/happy1195-mhs/HappyTemplate" ] || fail "mhs HappyTemplate missing"
[ -f "$GMP_PREFIX/lib/libgmp.a" ] || fail "static libgmp.a missing under $GMP_PREFIX"

mkdir -p "$ROOT/build/sources" \
	"$ROOT/build/ref-ghc-bootstrap/ghc66" \
	"$ROOT/build/ghc74-work/src" \
	"$ROOT/build/ghc74-work/ghc74-prefix/bin" \
	"$ROOT/build/ghc74-work/bin"

cp -a "$IN/happy-1.19.5.tar.gz" "$ROOT/build/sources/happy-1.19.5.tar.gz"
cp -a "$IN/alex-3.2.7.4.tar.gz" "$ROOT/build/sources/alex-3.2.7.4.tar.gz"
cp -a "$IN/cpp-template.sh" "$ROOT/build/ref-ghc-bootstrap/ghc66/cpp-template.sh"
cp -a "$IN/cmp-generated.sh" "$ROOT/build/ref-ghc-bootstrap/ghc66/cmp-generated.sh"
chmod 755 "$ROOT/build/ref-ghc-bootstrap/ghc66/cpp-template.sh" \
	"$ROOT/build/ref-ghc-bootstrap/ghc66/cmp-generated.sh"

# mtl 1.1.1.1 lives in the ghc-7.4.2 tree. The inner script does not unpack it.
tar -C "$ROOT/build/ghc74-work/src" -xjf "$IN/ghc-7.4.2-src.tar.bz2"
[ -f "$ROOT/build/ghc74-work/src/ghc-7.4.2/libraries/mtl/mtl.cabal" ] || fail "mtl.cabal missing"

cat > "$ROOT/build/ghc74-work/ghc74-prefix/bin/ghc" << 'EOF'
#!/bin/sh
exec /usr/bin/ghc74 "$@"
EOF
cat > "$ROOT/build/ghc74-work/ghc74-prefix/bin/ghc-pkg" << 'EOF'
#!/bin/sh
exec /usr/bin/ghc-pkg74 "$@"
EOF
chmod 755 "$ROOT/build/ghc74-work/ghc74-prefix/bin/ghc" \
	"$ROOT/build/ghc74-work/ghc74-prefix/bin/ghc-pkg"

# The inner script greps PATH for this path. Same flags as the ghc74 bootstrap
# gcc, so a link uses the private static GMP instead of the system shared one.
cat > "$ROOT/build/ghc74-work/bin/gcc" << EOF
#!/bin/bash
GMP="$GMP_PREFIX"
link=1
for a in "\$@"; do
	case "\$a" in
	-c|-E|-S|-M|-MM|-shared|--version|-dumpversion) link=0 ;;
	esac
done
args=(-I"\$GMP/include" -fno-pie "\$@")
if [ "\$link" = 1 ]; then
	args+=(-L"\$GMP/lib" -no-pie -Wl,-rpath,"\$GMP/lib")
fi
exec /usr/bin/gcc "\${args[@]}"
EOF
chmod 755 "$ROOT/build/ghc74-work/bin/gcc"

export LD_LIBRARY_PATH="$GMP_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$ROOT/build/ghc74-work/ghc74-prefix/bin:$ROOT/build/ghc74-work/bin:$PATH"
hash -r
command -v ghc | grep -q ghc74-prefix || fail "PATH ghc is $(command -v ghc)"
command -v gcc | grep -q '/ghc74-work/bin/gcc' || fail "PATH gcc is $(command -v gcc)"

python - "$IN/ghc74tools-inner.sh" "$ROOT/build/ghc74tools-inner.sh" << 'PY'
import sys
src, dst = sys.argv[1:]
text = open(src, encoding="utf-8").read()
if text.count("/media/space") != 1:
    sys.exit("expected one /media/space before adapt, found %s" % text.count("/media/space"))
repls = [
    ("ROOT=/media/space/repos/GHC-MicroHs-bootstrap\n", "ROOT=${STAGE:?}\n"),
    ("GMP=$ROOT/build/gmp-6.1.2-prefix\n", "GMP=${GMP_PREFIX:?}\n"),
    ("MHS_HAPPY=$ROOT/build/bin/happy\n", "MHS_HAPPY=/usr/bin/happy1195-mhs\n"),
    ("MHS_DATA=$ROOT/build/happy-mhs/datadir\n", "MHS_DATA=${DATADIR:?}/happy1195-mhs\n"),
]
for old, new in repls:
    n = text.count(old)
    if n != 1:
        sys.exit("adapt count %s for %r" % (n, old))
    text = text.replace(old, new, 1)
if "/media/space" in text:
    sys.exit("inner script still mentions /media/space")
if "--prefix=/usr" in text:
    sys.exit("inner script must not configure --prefix=/usr")
if "HAPPY_PREFIX=$WORK/happy-1.19.5-prefix\n" not in text:
    sys.exit("HAPPY_PREFIX assignment missing")
if "ALEX_PREFIX=$WORK/alex-3.2.7.4-prefix\n" not in text:
    sys.exit("ALEX_PREFIX assignment missing")
open(dst, "w", encoding="utf-8").write(text)
PY
chmod 755 "$ROOT/build/ghc74tools-inner.sh"
bash "$ROOT/build/ghc74tools-inner.sh"
[ -f "$ROOT/build/ghc74-tools/stamps/mtl.ok" ] || fail "mtl stamp missing"
[ -f "$ROOT/build/ghc74-tools/stamps/happy.ok" ] || fail "happy stamp missing"
[ -f "$ROOT/build/ghc74-tools/stamps/alex.ok" ] || fail "alex stamp missing"

HAPPY_SRC=$ROOT/build/ghc74-tools/src/happy-1.19.5
ALEX_SRC=$ROOT/build/ghc74-tools/src/alex-3.2.7.4
MTL_DB=$ROOT/build/ghc74-tools/mtl-prefix/lib/package.conf.d
[ -d "$HAPPY_SRC" ] || fail "happy source missing"
[ -d "$ALEX_SRC" ] || fail "alex source missing"
[ -d "$MTL_DB" ] || fail "mtl package db missing"
[ -x "$HAPPY_SRC/Setup" ] || fail "happy Setup missing"
[ -x "$ALEX_SRC/Setup" ] || fail "alex Setup missing"

# The script's templates() output is what the fixed point compared. Setup
# build's postBuild overwrites those files with ghc -E, which leaves modern
# cpp markers, so put the verified templates back before copy.
saved=$ROOT/tmp/happy-templates
rm -rf "$saved"
mkdir -p "$saved"
templates=(
	HappyTemplate
	HappyTemplate-ghc
	HappyTemplate-coerce
	HappyTemplate-arrays
	HappyTemplate-arrays-ghc
	HappyTemplate-arrays-coerce
	HappyTemplate-arrays-debug
	HappyTemplate-arrays-ghc-debug
	HappyTemplate-arrays-coerce-debug
	GLR_Base
	GLR_Lib
	GLR_Lib-ghc
	GLR_Lib-ghc-debug
)
for f in "${templates[@]}"; do
	[ -f "$HAPPY_SRC/$f" ] || fail "verified template missing: $f"
	cp -a "$HAPPY_SRC/$f" "$saved/$f"
done

rm -rf "$ROOT/dest" "$ROOT/cabal-copy"
mkdir -p "$ROOT/dest/bin" "$ROOT/dest/share"

(
	cd "$HAPPY_SRC"
	rm -rf dist
	./Setup configure -v0 --prefix=/usr --with-compiler=ghc --with-hc-pkg=ghc-pkg \
		--ghc-option=-rtsopts \
		--package-db="$MTL_DB"
	./Setup build -v0
	for f in "${templates[@]}"; do
		cp -a "$saved/$f" "$f"
	done
	rm -rf "$ROOT/cabal-copy"
	./Setup copy -v0 --destdir="$ROOT/cabal-copy"
)
happy_bin=$ROOT/cabal-copy/usr/bin/happy
happy_share=$ROOT/cabal-copy/usr/share/happy-1.19.5
[ -x "$happy_bin" ] || fail "cabal copy produced no usr/bin/happy"
[ -d "$happy_share" ] || fail "cabal copy produced no share/happy-1.19.5"
file "$happy_bin" | grep -q ELF || fail "rebuilt happy is not an ELF"
if grep -a -F -q '/media/space' "$happy_bin"; then
	fail "rebuilt happy contains /media/space"
fi
if grep -a -F -q 'happy-1.19.5-prefix' "$happy_bin"; then
	fail "rebuilt happy still points at the work prefix"
fi
grep -a -F -q '/usr/share/happy-1.19.5' "$happy_bin" || fail "happy datadir was not baked"
nshare=$(find "$happy_share" -maxdepth 1 -type f | wc -l | tr -d '[:space:]')
[ "$nshare" = 13 ] || fail "rebuilt happy share count $nshare"
install -m 755 "$happy_bin" "$ROOT/dest/bin/happy1195.real"
cp -a "$happy_share" "$ROOT/dest/share/happy-1.19.5"

(
	cd "$ALEX_SRC"
	rm -rf dist
	./Setup configure -v0 --prefix=/usr --with-compiler=ghc --with-hc-pkg=ghc-pkg \
		--ghc-option=-rtsopts
	./Setup build -v0
	rm -rf "$ROOT/cabal-copy"
	./Setup copy -v0 --destdir="$ROOT/cabal-copy"
)
alex_bin=$ROOT/cabal-copy/usr/bin/alex
alex_share=$ROOT/cabal-copy/usr/share/alex-3.2.7.4
[ -x "$alex_bin" ] || fail "cabal copy produced no usr/bin/alex"
[ -f "$alex_share/AlexTemplate.hs" ] || fail "alex AlexTemplate.hs missing"
[ -f "$alex_share/AlexWrappers.hs" ] || fail "alex AlexWrappers.hs missing"
file "$alex_bin" | grep -q ELF || fail "rebuilt alex is not an ELF"
if grep -a -F -q '/media/space' "$alex_bin"; then
	fail "rebuilt alex contains /media/space"
fi
if grep -a -F -q 'alex-3.2.7.4-prefix' "$alex_bin"; then
	fail "rebuilt alex still points at the work prefix"
fi
grep -a -F -q '/usr/share/alex-3.2.7.4' "$alex_bin" || fail "alex datadir was not baked"
install -m 755 "$alex_bin" "$ROOT/dest/bin/alex327.real"
cp -a "$alex_share" "$ROOT/dest/share/alex-3.2.7.4"
rm -rf "$ROOT/cabal-copy"

# readlink so a later hop can symlink this wrapper as "happy" or "alex"
# and still find the ELF beside the installed path.
write_wrapper() {
	local name=$1
	shift
	local rts=$*
	cat > "$ROOT/dest/bin/$name" << EOF
#!/bin/bash
set -eu
arg0=\$0
if [ ! -x "\$arg0" ] || [ "\$arg0" = "\${arg0#*/}" ]; then
	arg0=\$(command -v "\$0") || exit 1
fi
here=\$(CDPATH= cd -- "\$(dirname "\$(readlink -f "\$arg0")")" && pwd)
exec "\$here/${name}.real" ${rts} "\$@"
EOF
	chmod 755 "$ROOT/dest/bin/$name"
}
write_wrapper happy1195 +RTS -K64M -H128M -RTS
write_wrapper alex327 +RTS -K64M -RTS

[ ! -e "$ROOT/dest/bin/happy" ] || fail "refusing to ship /usr/bin/happy"
[ ! -e "$ROOT/dest/bin/alex" ] || fail "refusing to ship /usr/bin/alex"
[ ! -e "$ROOT/dest/share/generated" ] || fail "refusing to ship share/generated"
printf 'ghc74tools: staged %s\n' "$ROOT/dest"
