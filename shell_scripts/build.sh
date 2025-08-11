#!/bin/bash

###################### COPYRIGHT/COPYLEFT ######################

# (C) 2020 Michael Soegtrop

# Released to the public under the
# Creative Commons CC0 1.0 Universal License
# See https://creativecommons.org/publicdomain/zero/1.0/legalcode.txt

###################### BUILD ALL PACKAGES USING OPAM ######################

# This is set by the windows batch file and conflicts with the use of variables e.g. in VST
unset ARCH

function dump_opam_logs {
  if [ "${COQ_PLATFORM_DUMP_LOGS:-n}" == "y" ]
  then
    for log in $(opam config var root)/log/*
    do
      echo "==============================================================================="
      echo $log
      echo "==============================================================================="
      cat -n $log
    done
  fi
  return 1
}

opam config set jobs $COQ_PLATFORM_JOBS

# coq-fiat-crypto requires this - it sets the maximum stack size to 64MB
# Note that on MacOS the absolute maximum is ulimit -S -s 65520
# One can rise it as root on MacOS, but only for a root shell, not for the current shell
ulimit -S -s 65520

## --- Windows-only: Flocq/Flocq3 workaround (remake DB clean + disable native compiler), auto version detection
if [[ "$OSTYPE" == cygwin* ]]; then
  echo "[Windows] Preparing Flocq/Flocq3 workaround (auto-detected versions, win32+cygwin stanzas)"

  apply_overlay_for_pkg () {
    local pkg="$1"
    local ver
    # Which version would opam install for this pkg (given current repos/constraints)?
    ver="$(opam show -f version "$pkg" 2>/dev/null || true)"
    if [[ -z "$ver" ]]; then
      # Not available in current selection/repos; skip quietly
      return 0
    fi
    echo "  -> $pkg version detected by opam: $ver"

    local overlay="$HOME/opam-flocq-win-overlay"
    local pkgdir="$overlay/packages/$pkg/$pkg.$ver"
    mkdir -p "$pkgdir"

    cat > "$pkgdir/opam" <<'OPAM'
opam-version: "2.0"

build: [
  # --- Windows via native Win32 runner ---
  [ "sh" "-exc"
    "if [ -x ./remake ]; then \
       ./remake clean || true; \
       rm -f .remake.db .remake.db* 2>/dev/null || true; \
     fi" ] { os = "win32" }
  [ "env" "COQFLAGS=-native-compiler off" "COQEXTRAFLAGS=-native-compiler off" "./remake" "-d" "-j%{jobs}%" ] { os = "win32" }

  # --- Windows via Cygwin runner (opam reports os=cygwin) ---
  [ "bash" "-lc"
    "if [ -x ./remake ]; then \
       ./remake clean || true; \
       rm -f .remake.db .remake.db* 2>/dev/null || true; \
     fi" ] { os = "cygwin" }
  [ "bash" "-lc" "COQFLAGS='-native-compiler off' COQEXTRAFLAGS='-native-compiler off' ./remake -d -j%{jobs}%" ] { os = "cygwin" }

  # --- Other OSes ---
  [ "./remake" "-d" "-j%{jobs}%" ] { os != "win32" & os != "cygwin" }
]

install: [
  [ "./remake" "install" ]
]
OPAM

    # Refresh/add the local overlay with high priority (idempotent)
    opam repository remove flocq-win-local >/dev/null 2>&1 || true
    opam repository add flocq-win-local "file://$overlay" --priority=100 || true
    opam update
  }

  # Try for both package names depending on pick / Coq version
  apply_overlay_for_pkg "coq-flocq"
  apply_overlay_for_pkg "coq-flocq3"
fi

case "$COQ_PLATFORM_PARALLEL" in
  [pP]) 
    echo "===== INSTALL OPAM PACKAGES (PARALLEL) ====="
    if ! $COQ_PLATFORM_TIME opam install ${PACKAGES//PIN.}; then dump_opam_logs; fi
    for package in ${PACKAGES}
    do
      case $package in
      PIN.*)
        echo PINNING $package
        package_name="$(echo "$package" | cut -d '.' -f 2)"
        package_version="$(echo "$package" | cut -d '.' -f 3-)"
        if ! $COQ_PLATFORM_TIME opam pin --no-action ${package_name} ${package_version}; then dump_opam_logs; fi
        ;;
      esac
    done
    ;;
  [sS]) 
    echo "===== INSTALL OPAM PACKAGES (SEQUENTIAL) ====="
    for package in ${PACKAGES}
    do
      echo PROCESSING $package
      case $package in
      PIN.*)
        echo PROCESSING 1 $package
        package_name="$(echo "$package" | cut -d '.' -f 2)"
        package_version="$(echo "$package" | cut -d '.' -f 3-)"
        if ! $COQ_PLATFORM_TIME opam pin ${package_name} ${package_version}; then dump_opam_logs; fi
        ;;
      *)
        echo PROCESSING 2 $package
        if ! $COQ_PLATFORM_TIME opam install ${package}; then dump_opam_logs; fi
        ;;
      esac
    done
    ;;
  *)
    echo "Illegal value for COQ_PLATFORM_PARALLEL - aborting"
    false
    ;;
esac