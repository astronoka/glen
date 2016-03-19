#!/bin/bash

if [ "$DEBUG" != "" ]; then
  # BASH_XTRACEFD
  set -x
fi

shell=`basename "$SHELL"`
case "$shell" in
  bash) ;;
  *)
    echo "glen only supports bash shells." >&2
    exit 1
    ;;
esac

if ! type git > /dev/null; then
  echo "git command not found."
  exit 1
fi

uname="$(uname -a)"
os=
arch=
case "$uname" in
  Linux\ *) os=linux ;;
  Darwin\ *) os=darwin ;;
  FreeBSD\ *) os=freebsd ;;
esac
case "$uname" in
  *i386*) arch="386" ;;
  *x86_64*) arch="amd64" ;;
esac

tar=${TAR-tar}

ensure_dir () {
  if ! [ -d "$1" ]; then
    mkdir -p -- "$1" || die "couldn't create $1"
  fi
}

remove_dir () {
  if [ -d "$1" ]; then
    rm -rf -- "$1" || die "could not remove $1"
  fi
}

die () {
  echo "$@" >&2
  exit 1
}

error () {
  echo "$@" >&2
}

download_src () {
  local repo="$GLEN_SRC"
  if ! [ -d "$repo" ]; then
    git clone https://go.googlesource.com/go "$repo"
    #git -C "$repo" clone --quiet https://go.googlesource.com/go
  else
    cd "$repo" && git fetch --prune
  fi
}

listup_src_tags () {
  local repo="$GLEN_SRC"
  local tags=(`cd "$repo" && git tag`)
  echo ${tags[@]}
}

listup_installed_versions () {
  local installed_versions=(`ls -- "$GLEN_ROOT"`)
  echo ${installed_versions[@]}
}

if ! [ -d "$GLEN_DIR" ]; then
  if [ -d "$HOME" ]; then
    GLEN_DIR="$HOME"/.glen
  else
    GLEN_DIR=/usr/local/glen
  fi
fi

output_activate_script () {
  local label="$1"
  local version="$2"
  local go_path="$3"
  local go_root="\$GLEN_ROOT/$version"

  local go_bin_path="$go_path/bin":"\$GLEN_ROOT/$version/bin"
  local ps1="($label:$version)\$PS1"

  cat <<ACTIVATE_SCRIPT
#!/bin/sh

[ -f \$GLEN_DIR/.glenrc ] && . \$GLEN_DIR/.glenrc || true

export GOROOT="$go_root"
export GOPATH="$go_path"
export PS1="$ps1"
export PATH="$go_bin_path:\$PATH"

ACTIVATE_SCRIPT
}

glen_tags () {
  download_src
  local tags=(`listup_src_tags`)
  for tag in "${tags[@]}"; do
    if [[ "$tag" =~ ^go.*$ ]]; then
      echo "$tag"
    fi
  done
}

glen_list () {
  download_src
  local installed_versions=(`listup_installed_versions`)
  for version in "${installed_versions[@]}"; do
    echo "$version"
  done
}

glen_installed () {
  local version="$1"
  [ -x "$GLEN_ROOT/$version/bin/go" ] || return 1
}

glen_install () {
  download_src

  local version="$1"
  if [ -z "$version" ]; then
    error "usage: glen install <version>"
    die "version required."
  fi
  if glen_installed "$version"; then
    error "already installed: $version"
    return 0
  fi

  local install="$GLEN_ROOT/$version"
  ensure_dir "$install"

  build "$version" "$install"
  local ret=$?
  if [ $ret -ne 0 ]; then
    remove_dir "$install"
  else
    local go_path_dir="$install/glen"
    ensure_dir "$go_path_dir"
    local script=`output_activate_script glen "$version" "\$GLEN_ROOT/$version/glen"`
    echo "$script" > "$install/activate.sh"
    echo "successfully installed: $version" >&2
  fi
  return $ret
}

glen_uninstall () {
  local version="$1"
  if [ -z "$version" ]; then
    error "usage: glen uninstall <version>"
    die "version required."
  fi
  if ! glen_installed "$version"; then
    return 0
  fi
  local install="$GLEN_ROOT/$version"
  remove_dir "$install"
}

glen_use () {
  local version="$1"
  if [ -z "$version" ]; then
    error "usage: glen use <version>"
    die "version required."
  fi
  if ! glen_installed "$version"; then
    error "version not installed: $version"
    error "-- installed version"
    local installed_versions=(`listup_installed_versions`)
    for version in "${installed_versions[@]}"; do
      error "$version"
    done
    die "--"
  fi
  local install="$GLEN_ROOT/$version"
  local activate_script="$install/activate.sh"
  if [ ! -f "$activate_script" ]; then
    die "'$install' does not contain an activate script."
  fi

  GLEN_ENV_NAME=$version \
    "$SHELL" --rcfile "$activate_script"

  exit_code=$?
  hash -r
  return $exit_code
}

build () {
  local version="$1"
  local godir="$2"
  local repo="$GLEN_SRC"
  local datetime=`date +"%Y%m%d%H%M%S"`
  local logfile="$GLEN_BUILDLOG/$version-$datetime.log"

  if [ -n "$os" ]; then
    local archive_name="$version.$os-$arch.tar.gz"
    local archive_url="https://storage.googleapis.com/golang/$archive_name"
    local local_archive_file="$GLEN_SRC/$archive_name"
    download_file -#Lf "$archive_url" > "$local_archive_file"
    if [ $? -ne 0 ]; then
      rm "$local_archive_file"
    else
      $tar xzf "$local_archive_file" -C "$godir" --strip-components 1
      if [ $? -ne 0 ]; then
        rm "$local_archive_file"
        glen_uninstall "$version"
        error "binary unpack failed, trying source."
      fi
      echo "installed from binary" >&2
      return 0
    fi
    echo "binary download failed, trying source." >&2
  fi

  # To build Go 1.x, for x ≥ 5, it will be necessary
  # to have Go 1.4 (or newer) installed already, in $GOROOT_BOOTSTRAP.
  # see also: https://docs.google.com/document/d/1OaatvGhEAq7VseQ9kkavxKNAfepWy2yhPUBs96FGV28/edit
  if [[ "$version" =~ ^go([0-9]+)(\.([0-9]+)(\.([0-9]+))?)?$ ]]; then
    local major_ver="${BASH_REMATCH[1]}"
    local minor_ver="${BASH_REMATCH[3]:-0}"
    local patch_ver_unused="${BASH_REMATCH[5]:-0}"
    if [ $major_ver -ge 1 -a $minor_ver -ge 5 ]; then
      local bootstrap_go_version="go1.4.3"
      if ! glen_installed "$bootstrap_go_version"; then
        echo "to install ${version}, ${bootstrap_go_version} required."
        echo "auto install ${bootstrap_go_version}"
        if ! glen_install "$bootstrap_go_version"; then
          die "install ${bootstrap_go_version} failed."
        fi
      fi
      export GOROOT_BOOTSTRAP="$GLEN_ROOT/$bootstrap_go_version/"
    fi
  fi

  cd "$repo"
  if eval "git checkout -f "$version" &> $logfile"; then
    git clean -fd
    cd src
    rm -rf pkg && rm -rf bin
    export GOROOT_FINAL="$godir"
    ./all.bash 2>&1 | tee -a "$logfile"
    if [[ "${PIPESTATUS[0]}" -eq 0 ]]; then
      cd "$repo"
      rsync -av --exclude='.git*' . "$godir" 2>&1 | tee -a "$logfile"
    else
      error "build failed. : $logfile"
      return 1
    fi
  else
    error "invalid version. : $version"
    return 1
  fi
}

download_file () {
  curl -H "user-agent:glen/$(curl --version | head -n1)" "$@"
  return $?
}

glen_env () {
  local cmd="$1"
  shift
  case $cmd in
    list | create | delete | use )
      cmd="glen_env_$cmd"
      ;;
    * )
      cmd="glen_help"
      ;;
  esac
  $cmd "$@"
  local ret=$?
  if [ $ret -eq 0 ]; then
    return 0
  else
    echo "env failed with code=$ret" >&2
    return $ret
  fi
}

glen_env_list () {
  local envs=(`ls -- "$GLEN_ENV"`)
  for env in "${envs[@]}"; do
    echo "$env"
  done
}

glen_env_create () {
  local envname="$1"
  local version="$2"
  if [ -z "$envname" ]; then
    error "usage: glen env create <envname> <version>"
    die "envname required."
  fi
  if [ -z "$version" ]; then
    error "usage: glen env create <envname> <version>"
    die "version required."
  fi
  if [ -d "$GLEN_ENV/$envname" ]; then
    error "already exist: $envname"
    return 0
  fi

  if ! glen_installed "$version"; then
    error "version not installed: $version"
    error "-- installed version"
    local installed_versions=(`listup_installed_versions`)
    for version in "${installed_versions[@]}"; do
      error "$version"
    done
    die "--"
  fi

  local go_path_dir="$GLEN_ENV/$envname"
  ensure_dir "$go_path_dir"

  local script=`output_activate_script "$envname" "$version" "\$GLEN_ENV/$envname"`
  echo "$script" > "$go_path_dir/activate.sh"
}

glen_env_delete () {
  local envname="$1"
  if [ -z "$envname" ]; then
    die "envname required."
  fi
  local env="$GLEN_ENV/$envname"
  remove_dir "$env"
}

glen_env_use () {
  local envname="$1"
  if [ -z "$envname" ]; then
    die "envname required."
  fi

  if [ "$envname" == "$GLEN_ENV_NAME" ]; then
    error "already using env $envname" >&2
    exit 0
  fi

  local activate_script="$GLEN_ENV/$envname/activate.sh"
  if [ ! -f "$activate_script" ]; then
    die "env not found. : $envname"
  fi

  GLEN_ENV_NAME=$envname \
    "$SHELL" --rcfile "$activate_script"

  exit_code=$?
  hash -r
  return $exit_code
}

glen_vendor () {
  local cmd="$1"
  shift
  case $cmd in
    init | use )
      cmd="glen_vendor_$cmd"
      ;;
    * )
      cmd="glen_help"
      ;;
  esac
  $cmd "$@"
  local ret=$?
  if [ $ret -eq 0 ]; then
    return 0
  else
    echo "failed with code=$ret" >&2
    return $ret
  fi
}

glen_vendor_init () {
  local version="$1"
  if [ -z "$version" ]; then
    error "usage: glen vendor init <version>"
    die "version required."
  fi

  if ! glen_installed "$version"; then
    error "version not installed: $version"
    error "-- installed version"
    local installed_versions=(`listup_installed_versions`)
    for version in "${installed_versions[@]}"; do
      error "$version"
    done
    die "--"
  fi

  local workspace_dir=(`pwd`)
  local rcfile="$workspace_dir/glenrc"

  if [ -f "$rcfile" ]; then
    die "glenrc exist! already initialized"
  fi

  local go_path_dir="$workspace_dir/vendor"
  ensure_dir "$go_path_dir"
  echo "create vendor directory" >&2

  #local label="${workspace_dir##*/}"
  local label="\`basename \$(pwd)\`"

  local go_path="\`pwd\`/vendor"
  local script=`output_activate_script "$label" "$version" "$go_path"`
  echo "$script" > "$rcfile"
  echo "create glenrc" >&2

  echo "successfully initialized: $workspace_dir" >&2
}

glen_vendor_use () {
  local workspace_dir=(`pwd`)
  local activate_script="$workspace_dir/glenrc"
  if [ ! -f "$activate_script" ]; then
    die "'$workspace_dir' does not contain an activate script."
  fi

  local label="${workspace_dir##*/}"

  GLEN_ENV_NAME=$label \
    "$SHELL" --rcfile "$activate_script"

  exit_code=$?
  hash -r
  return $exit_code
}

glen_tools () {
  if [ -z "$GLEN_ENV_NAME" ]; then
    die "glen is not active"
  fi
  local tools_file="$GLEN_DIR/tools.txt"
  if [ ! -f "$tools_file" ]; then
    echo "tools.txt not exist on $GLEN_DIR" >&2
    return 0
  fi
  local tools=(`cat $tools_file`)
  for tool in "${tools[@]}"; do
    echo "go get $tool into $GOPATH"
    go get "$tool"
  done
}

main () {

  export GLEN_DIR
  ensure_dir "$GLEN_DIR"

  export GLEN_SRC="$GLEN_DIR/src"
  export GLEN_BUILDLOG="$GLEN_DIR/buildlog"
  export GLEN_ROOT="$GLEN_DIR/installed"
  export GLEN_ENV="$GLEN_DIR/env"
  ensure_dir "$GLEN_BUILDLOG"
  ensure_dir "$GLEN_ROOT"
  ensure_dir "$GLEN_ENV"

  local cmd="$1"
  shift
  case $cmd in
    version | list | tags | update | install | uninstall | \
    use | env | vendor | tools )
      cmd="glen_$cmd"
      ;;
    * )
      cmd="glen_help"
      ;;
  esac
  $cmd "$@"
  local ret=$?
  if [ $ret -eq 0 ]; then
    exit 0
  else
    echo "failed with code=$ret" >&2
    exit $ret
  fi
}

glen_version () {
  echo "0.1.2"
}

glen_help () {
  cat <<EOF

Usage: glen <cmd>

Commands:

version                         Print glen version
help                            Output help text
install <version>               Install the version passed (ex: go1.5.3)
uninstall <version>             Delete the install for <version>
use <version>                   Activate specified <version>
list                            List installed versions
tags                            List available versions (tags)

env list                        List environments
env create <envname> <version>  Create environment
env delete <envname>            Delete environment
env use    <envname>            Activate environment

vendor init <version>           Initialize current directory as workspace
vendor use                      Activate current directory as workspace

tools                           Install develop tools (goimports,gorename...)

EOF
}

main "$@"
