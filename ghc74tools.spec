%global debug_package %{nil}
Summary:	Happy 1.19.5 and Alex 3.2.7.4 built by GHC 7.4.2
Name:		ghc74tools
Version:	1.19.5
Release:	1
License:	BSD
Group:		Development/Other
Url:		https://hackage.haskell.org/package/happy
# Complement of distro happy and alex. The binaries are happy1195 and
# alex327, so no Epoch. mtl is built in the work tree and not installed.
ExclusiveArch:	x86_64 znver1
# happy-1.19.5.tar.gz sha256 62f03ac11d7b4b9913f212f5aa2eee1087f3b46dc07d799d41e1854ff02843da
# alex-3.2.7.4.tar.gz sha256 8a13fa01ea00883aa3d75d15ce848835b18631b8c9a4966961492d7c6095226f
# ghc-7.4.2-src.tar.bz2 sha256 f2ee1289a33cc70539287129841acc7eaf16112bb60c59b5a6ee91887bfd836d
Source0:	happy-1.19.5.tar.gz
Source1:	alex-3.2.7.4.tar.gz
Source2:	ghc-7.4.2-src.tar.bz2
Source3:	ghc74tools-inner.sh
Source4:	cpp-template.sh
Source5:	cmp-generated.sh
Source6:	ghc74tools-build.sh
Source7:	%{name}.rpmlintrc

BuildRequires:	ghc74
BuildRequires:	gmp612
BuildRequires:	gcc
BuildRequires:	make
BuildRequires:	patch
BuildRequires:	perl
BuildRequires:	python
BuildRequires:	diffutils
BuildRequires:	binutils
BuildRequires:	file
BuildRequires:	findutils
BuildRequires:	coreutils
BuildRequires:	util-linux
BuildRequires:	grep
BuildRequires:	sed
BuildRequires:	tar
BuildRequires:	gzip
BuildRequires:	cpphs-mhs
# happy1195-mhs only sets HAPPY_DATADIR. It is installed by ghc66.
BuildRequires:	ghc66

%description
Happy 1.19.5 and Alex 3.2.7.4 compiled by the packaged ghc74.
The first parsers come from the MicroHs happy (happy1195-mhs).
The mtl library these tools need is registered only in the work
tree and is not installed. No upstream bindist is used.

Installed as happy1195 and alex327 so they do not replace the
distribution happy and alex packages. Each wrapper runs the real
binary with a larger RTS stack.

%prep
	set -eu
	cd %{_builddir}
	rm -rf ghc74tools-root
	mkdir -p ghc74tools-root/incoming
	cp -a %{SOURCE0} ghc74tools-root/incoming/happy-1.19.5.tar.gz
	cp -a %{SOURCE1} ghc74tools-root/incoming/alex-3.2.7.4.tar.gz
	cp -a %{SOURCE2} ghc74tools-root/incoming/ghc-7.4.2-src.tar.bz2
	cp -a %{SOURCE3} ghc74tools-root/incoming/ghc74tools-inner.sh
	cp -a %{SOURCE4} ghc74tools-root/incoming/cpp-template.sh
	cp -a %{SOURCE5} ghc74tools-root/incoming/cmp-generated.sh
	cp -a %{SOURCE6} ghc74tools-root/incoming/ghc74tools-build.sh
	chmod 755 ghc74tools-root/incoming/ghc74tools-build.sh
	set +u

%build
	set -eu
	bash "%{_builddir}/ghc74tools-root/incoming/ghc74tools-build.sh" "%{_builddir}/ghc74tools-root" "%{_libdir}"
	set +u

%install
	set -eu
	dest=%{_builddir}/ghc74tools-root/dest
	mkdir -p %{buildroot}%{_bindir} %{buildroot}%{_datadir}
	cp -a "$dest/bin/." %{buildroot}%{_bindir}/
	cp -a "$dest/share/." %{buildroot}%{_datadir}/
	test -x %{buildroot}%{_bindir}/happy1195
	test -x %{buildroot}%{_bindir}/happy1195.real
	test -x %{buildroot}%{_bindir}/alex327
	test -x %{buildroot}%{_bindir}/alex327.real
	test ! -e %{buildroot}%{_bindir}/happy
	test ! -e %{buildroot}%{_bindir}/alex
	file %{buildroot}%{_bindir}/happy1195.real | grep -q ELF
	file %{buildroot}%{_bindir}/alex327.real | grep -q ELF
	test -f %{buildroot}%{_datadir}/happy-1.19.5/HappyTemplate
	test -f %{buildroot}%{_datadir}/alex-3.2.7.4/AlexTemplate.hs
	test -f %{buildroot}%{_datadir}/alex-3.2.7.4/AlexWrappers.hs
	set +u

%files
%{_bindir}/happy1195
%{_bindir}/happy1195.real
%{_bindir}/alex327
%{_bindir}/alex327.real
%{_datadir}/happy-1.19.5/
%{_datadir}/alex-3.2.7.4/

%check
	set -eu
	export PATH=%{buildroot}%{_bindir}:$PATH
	hash -r
	b=$(command -v happy1195)
	a=$(command -v alex327)
	v=$("$b" --version | tr -d '\r')
	printf '%s\n' "$v" | grep -q 'Happy Version 1.19.5'
	v2=$("$b" --version | tr -d '\r')
	printf '%s\n' "$v2" | grep -q 'Happy Version 1.19.5'
	w=$("$a" --version | tr -d '\r')
	printf '%s\n' "$w" | grep -q 'Alex version 3.2.7.4'
	w2=$("$a" --version | tr -d '\r')
	printf '%s\n' "$w2" | grep -q 'Alex version 3.2.7.4'
	set +u
