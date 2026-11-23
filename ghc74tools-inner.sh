#!/bin/bash
# mtl 1.1.1.1, happy 1.19.5 and alex 3.2.7.4, built by the in-chain GHC 7.4.2.
# happy's -agc templates and alex's lexer are taken to a fixed point.
# 7.4.2 links executables with RtsOptsSafeOnly, so -K/-H are rejected unless
# the executable is linked with -rtsopts. The installed happy and alex are
# then wrapped so Cabal's absolute-path call still gets a 64M stack.
set -Euo pipefail

ROOT=/media/space/repos/GHC-MicroHs-bootstrap
R=$ROOT/build/ref-ghc-bootstrap
WORK=$ROOT/build/ghc74-tools
GHC=$ROOT/build/ghc74-work/ghc74-prefix
GMP=$ROOT/build/gmp-6.1.2-prefix
TREE=$ROOT/build/ghc74-work/src/ghc-7.4.2
MHS_HAPPY=$ROOT/build/bin/happy
MHS_DATA=$ROOT/build/happy-mhs/datadir
CPP=$R/ghc66/cpp-template.sh
CMP=$R/ghc66/cmp-generated.sh
MTL_PREFIX=$WORK/mtl-prefix
HAPPY_PREFIX=$WORK/happy-1.19.5-prefix
ALEX_PREFIX=$WORK/alex-3.2.7.4-prefix

export TMPDIR=$WORK/tmp
export LD_LIBRARY_PATH="$GMP/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
unset GHC_PACKAGE_PATH || true
mkdir -p "$TMPDIR" "$WORK/logs" "$WORK/stamps" "$WORK/src"

exec 9>"$WORK/build-tools.lock"
flock -n 9 || { printf 'TOOLS_FAILED: another build holds %s\n' "$WORK/build-tools.lock"; exit 1; }

phase() { printf 'TOOLS_PHASE %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail() { printf 'TOOLS_FAILED: %s\n' "$*"; exit 1; }
trap 's=$?; printf "TOOLS_FAILED: line %s status %s\n" "$LINENO" "$s"; exit "$s"' ERR

printf '%s\n' "$$" > "$WORK/build-tools.pid"
ulimit -s unlimited 2>/dev/null || true
phase "start pid $$"

[ -x "$GHC/bin/ghc" ] || fail "7.4.2 missing: $GHC/bin/ghc"
ver=$("$GHC/bin/ghc" --numeric-version | tr -d '[:space:]')
[ "$ver" = "7.4.2" ] || fail "boot numeric-version is '$ver'"
[ -x "$MHS_HAPPY" ] || fail "mhs happy missing: $MHS_HAPPY"
[ -f "$MHS_DATA/HappyTemplate" ] || fail "mhs happy template missing: $MHS_DATA/HappyTemplate"
[ -f "$CPP" ] || fail "cpp-template.sh missing"
[ -f "$TREE/libraries/mtl/mtl.cabal" ] || fail "mtl source missing"
[ -f "$ROOT/build/sources/happy-1.19.5.tar.gz" ] || fail "happy tarball missing"
[ -f "$ROOT/build/sources/alex-3.2.7.4.tar.gz" ] || fail "alex tarball missing"

clean=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -e '\.ghcup' -e '\.cabal' -e '/ghc66-work/' -e '/ghc610-work/' -e '/ghc612-work/' -e '/ghc74-work/' -e '/ghc74-tools/' | paste -sd: -)
export PATH="$GHC/bin:$ROOT/build/ghc74-work/bin:$clean"
export CC="$ROOT/build/ghc74-work/bin/gcc"
hash -r
command -v ghc | grep -q ghc74-prefix || fail "PATH ghc is $(command -v ghc)"
command -v gcc | grep -q '/ghc74-work/bin/gcc' || fail "PATH gcc is $(command -v gcc)"
phase "boot compiler 7.4.2"

# -K is not a safe RTS option on this compiler. Prove -rtsopts before the real builds.
rm -rf "$WORK/rts-probe"
mkdir -p "$WORK/rts-probe"
printf 'main = putStrLn "rts-ok"\n' > "$WORK/rts-probe/R.hs"
ghc -v0 -rtsopts --make "$WORK/rts-probe/R.hs" -o "$WORK/rts-probe/R"
got=$("$WORK/rts-probe/R" +RTS -K8M -H16M -RTS)
[ "$got" = "rts-ok" ] || fail "rts probe printed '$got'"
phase "rtsopts probe ok"

mhs_ver=$("$MHS_HAPPY" +RTS -K64M -H32M -RTS --version | tr -d '\r')
printf '%s\n' "$mhs_ver" | grep -q 'Happy Version 1.19.5' || fail "mhs happy version '$mhs_ver'"
phase "mhs happy 1.19.5"

if [ ! -f "$WORK/stamps/mtl.ok" ]; then
	phase "mtl unpack"
	rm -rf "$WORK/src/mtl" "$MTL_PREFIX"
	mkdir -p "$WORK/src" "$MTL_PREFIX/lib"
	/bin/cp -a "$TREE/libraries/mtl" "$WORK/src/mtl"
	rm -rf "$WORK/src/mtl/dist" "$WORK/src/mtl/dist-install"
	cd "$WORK/src/mtl"
	grep -q '^Version: *1\.1\.1\.1$' mtl.cabal || fail "mtl.cabal version"
	ghc-pkg init "$MTL_PREFIX/lib/package.conf.d"
	phase "mtl build"
	ghc --make -v0 Setup.hs -o Setup
	./Setup configure -v0 --prefix="$MTL_PREFIX" --with-compiler=ghc --with-hc-pkg=ghc-pkg \
		--package-db="$MTL_PREFIX/lib/package.conf.d"
	./Setup build -v0
	./Setup install -v0
	ghc-pkg list --package-conf="$MTL_PREFIX/lib/package.conf.d" --simple-output > "$WORK/logs/mtl-pkg.txt"
	grep -qx 'mtl-1.1.1.1' "$WORK/logs/mtl-pkg.txt" || fail "mtl db is $(tr '\n' ' ' < "$WORK/logs/mtl-pkg.txt")"
	touch "$WORK/stamps/mtl.ok"
fi
phase "mtl 1.1.1.1 registered"

if [ ! -f "$WORK/stamps/happy.ok" ]; then
	phase "happy unpack"
	rm -rf "$WORK/src/happy-1.19.5" "$HAPPY_PREFIX"
	tar -C "$WORK/src" -xzf "$ROOT/build/sources/happy-1.19.5.tar.gz"
	cd "$WORK/src/happy-1.19.5"
	mkdir shipped grammar
	/bin/mv -f dist/build/happy/happy-tmp/Parser.hs dist/build/happy/happy-tmp/AttrGrammarParser.hs shipped/
	rm -rf dist
	/bin/mv -f src/Parser.ly src/AttrGrammarParser.ly grammar/
	grep -q '^-- parser produced by Happy Version 1\.19\.4$' shipped/Parser.hs || fail "shipped Parser.hs is not happy 1.19.4"
	phase "happy Setup"
	ghc --make -v0 Setup.lhs -o Setup
	t() { sh "$CPP" ghc "templates/$1" "$2" "${@:3}"; }
	templates() {
		t GenericTemplate.hs HappyTemplate
		t GenericTemplate.hs HappyTemplate-ghc -DHAPPY_GHC
		t GenericTemplate.hs HappyTemplate-coerce -DHAPPY_GHC -DHAPPY_COERCE
		t GenericTemplate.hs HappyTemplate-arrays -DHAPPY_ARRAY
		t GenericTemplate.hs HappyTemplate-arrays-ghc -DHAPPY_ARRAY -DHAPPY_GHC
		t GenericTemplate.hs HappyTemplate-arrays-coerce -DHAPPY_ARRAY -DHAPPY_GHC -DHAPPY_COERCE
		t GenericTemplate.hs HappyTemplate-arrays-debug -DHAPPY_ARRAY -DHAPPY_DEBUG
		t GenericTemplate.hs HappyTemplate-arrays-ghc-debug -DHAPPY_ARRAY -DHAPPY_GHC -DHAPPY_DEBUG
		t GenericTemplate.hs HappyTemplate-arrays-coerce-debug -DHAPPY_ARRAY -DHAPPY_GHC -DHAPPY_COERCE -DHAPPY_DEBUG
		t GLR_Base.hs GLR_Base
		t GLR_Lib.hs GLR_Lib
		t GLR_Lib.hs GLR_Lib-ghc -DHAPPY_GHC
		t GLR_Lib.hs GLR_Lib-ghc-debug -DHAPPY_GHC -DHAPPY_DEBUG
		local f
		for f in HappyTemplate HappyTemplate-ghc HappyTemplate-coerce HappyTemplate-arrays \
			HappyTemplate-arrays-ghc HappyTemplate-arrays-coerce HappyTemplate-arrays-debug \
			HappyTemplate-arrays-ghc-debug HappyTemplate-arrays-coerce-debug \
			GLR_Base GLR_Lib GLR_Lib-ghc GLR_Lib-ghc-debug
		do
			[ -f "$f" ] || fail "missing template $f"
		done
		if grep -n '^# ' HappyTemplate HappyTemplate-ghc HappyTemplate-coerce HappyTemplate-arrays \
			HappyTemplate-arrays-ghc HappyTemplate-arrays-coerce HappyTemplate-arrays-debug \
			HappyTemplate-arrays-ghc-debug HappyTemplate-arrays-coerce-debug \
			GLR_Base GLR_Lib GLR_Lib-ghc GLR_Lib-ghc-debug
		then
			fail "cpp line markers remain in happy templates"
		fi
	}
	build() {
		local gen=$1
		rm -rf dist
		./Setup configure -v0 --prefix="$PWD/inst-$gen" --with-compiler=ghc --with-hc-pkg=ghc-pkg \
			--ghc-option=-rtsopts \
			--package-db="$MTL_PREFIX/lib/package.conf.d"
		./Setup build -v0
		templates
		./Setup install -v0
		/bin/cp -f "inst-$gen/bin/happy" "happy-$gen"
	}
	regen() {
		local gen=$1 p
		mkdir -p "gen$gen"
		for p in Parser AttrGrammarParser; do
			"./happy-$gen" +RTS -K64M -H128M -RTS -agc "grammar/$p.ly" -o "gen$gen/$p.hs"
		done
	}
	phase "happy gen0 with mhs happy"
	for p in Parser AttrGrammarParser; do
		HAPPY_DATADIR="$MHS_DATA" "$MHS_HAPPY" +RTS -K64M -H128M -RTS "grammar/$p.ly" -o "src/$p.hs"
	done
	phase "happy build 1"
	build 1
	regen 1
	/bin/cp -f gen1/Parser.hs gen1/AttrGrammarParser.hs src/
	phase "happy build 2"
	build 2
	regen 2
	phase "happy compare"
	for p in Parser AttrGrammarParser; do
		sed 's/^-- parser produced by Happy Version 1\.19\.4$/-- parser produced by Happy Version 1.19.5/' "shipped/$p.hs" > "shipped/$p.hs.v"
		grep -v '^import Control.Monad (ap)$' "gen1/$p.hs" > "gen1/$p.hs.v"
		sh "$CMP" "gen1/$p.hs.v" "shipped/$p.hs.v"
	done
	cmp gen1/Parser.hs gen2/Parser.hs
	cmp gen1/AttrGrammarParser.hs gen2/AttrGrammarParser.hs
	phase "happy fixed point"
	phase "happy install"
	rm -rf dist
	./Setup configure -v0 --prefix="$HAPPY_PREFIX" --with-compiler=ghc --with-hc-pkg=ghc-pkg \
		--ghc-option=-rtsopts \
		--package-db="$MTL_PREFIX/lib/package.conf.d"
	./Setup build -v0
	templates
	./Setup install -v0
	mkdir -p "$HAPPY_PREFIX/share/generated"
	/bin/cp -f gen2/*.hs "$HAPPY_PREFIX/share/generated/"
	hver=$("$HAPPY_PREFIX/bin/happy" --version | tr -d '\r')
	printf '%s\n' "$hver" | grep -q 'Happy Version 1.19.5' || fail "installed happy '$hver'"
	nshare=$(find "$HAPPY_PREFIX/share/happy-1.19.5" -maxdepth 1 -type f | wc -l | tr -d '[:space:]')
	[ "$nshare" = "13" ] || fail "happy share count $nshare"
	cmp <("$HAPPY_PREFIX/bin/happy" -agc grammar/Parser.ly -o /dev/stdout) gen2/Parser.hs
	# Wrap after the byte compare so the installed path Cabal records grows the stack.
	/bin/mv -f "$HAPPY_PREFIX/bin/happy" "$HAPPY_PREFIX/bin/happy.real"
	cat > "$HAPPY_PREFIX/bin/happy" <<'EOF'
#!/bin/bash
exec "$(dirname "$0")/happy.real" +RTS -K64M -H128M -RTS "$@"
EOF
	chmod +x "$HAPPY_PREFIX/bin/happy"
	hver=$("$HAPPY_PREFIX/bin/happy" --version | tr -d '\r')
	printf '%s\n' "$hver" | grep -q 'Happy Version 1.19.5' || fail "wrapped happy '$hver'"
	cmp <("$HAPPY_PREFIX/bin/happy" -agc grammar/Parser.ly -o /dev/stdout) gen2/Parser.hs
	touch "$WORK/stamps/happy.ok"
fi
phase "happy 1.19.5 installed"

if [ ! -f "$WORK/stamps/alex.ok" ]; then
	phase "alex unpack"
	rm -rf "$WORK/src/alex-3.2.7.4" "$ALEX_PREFIX"
	tar -C "$WORK/src" -xzf "$ROOT/build/sources/alex-3.2.7.4.tar.gz"
	cd "$WORK/src/alex-3.2.7.4"
	mkdir shipped grammar
	/bin/mv -f src/Parser.hs src/Scan.hs shipped/
	/bin/cp -f src/Parser.y.boot grammar/Parser.y
	/bin/cp -f src/Scan.x.boot grammar/Scan.x
	phase "alex Setup"
	ghc --make -v0 Setup.hs -o Setup
	build() {
		local gen=$1
		rm -rf dist
		./Setup configure -v0 --prefix="$PWD/inst-$gen" --with-compiler=ghc --with-hc-pkg=ghc-pkg \
			--ghc-option=-rtsopts
		./Setup build -v0
		./Setup install -v0
		/bin/cp -f "inst-$gen/bin/alex" "alex-$gen"
	}
	phase "alex gen0 parser"
	"$HAPPY_PREFIX/bin/happy" grammar/Parser.y -o src/Parser.hs
	/bin/cp -f shipped/Scan.hs src/Scan.hs
	phase "alex build 1"
	build 1
	mkdir -p gen1 gen2
	./alex-1 +RTS -K64M -RTS -g grammar/Scan.x -o gen1/Scan.hs
	/bin/cp -f gen1/Scan.hs src/Scan.hs
	phase "alex build 2"
	build 2
	./alex-2 +RTS -K64M -RTS -g grammar/Scan.x -o gen2/Scan.hs
	phase "alex compare"
	sh "$CMP" gen1/Scan.hs shipped/Scan.hs
	cmp gen1/Scan.hs gen2/Scan.hs
	phase "alex fixed point"
	phase "alex install"
	rm -rf dist
	./Setup configure -v0 --prefix="$ALEX_PREFIX" --with-compiler=ghc --with-hc-pkg=ghc-pkg \
		--ghc-option=-rtsopts
	./Setup build -v0
	./Setup install -v0
	mkdir -p "$ALEX_PREFIX/share/generated"
	/bin/cp -f gen2/Scan.hs src/Parser.hs "$ALEX_PREFIX/share/generated/"
	aver=$("$ALEX_PREFIX/bin/alex" --version | tr -d '\r')
	printf '%s\n' "$aver" | grep -q 'Alex version 3.2.7.4' || fail "installed alex '$aver'"
	cmp <("$ALEX_PREFIX/bin/alex" -g grammar/Scan.x -o /dev/stdout) gen2/Scan.hs
	/bin/mv -f "$ALEX_PREFIX/bin/alex" "$ALEX_PREFIX/bin/alex.real"
	cat > "$ALEX_PREFIX/bin/alex" <<'EOF'
#!/bin/bash
exec "$(dirname "$0")/alex.real" +RTS -K64M -RTS "$@"
EOF
	chmod +x "$ALEX_PREFIX/bin/alex"
	aver=$("$ALEX_PREFIX/bin/alex" --version | tr -d '\r')
	printf '%s\n' "$aver" | grep -q 'Alex version 3.2.7.4' || fail "wrapped alex '$aver'"
	cmp <("$ALEX_PREFIX/bin/alex" -g grammar/Scan.x -o /dev/stdout) gen2/Scan.hs
	touch "$WORK/stamps/alex.ok"
fi
phase "alex 3.2.7.4 installed"

printf 'TOOLS_DONE happy 1.19.5 at %s alex 3.2.7.4 at %s\n' "$HAPPY_PREFIX/bin/happy" "$ALEX_PREFIX/bin/alex"
