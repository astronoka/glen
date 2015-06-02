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

download_src_if_not_exist () {
  local repo="$GLEN_SRC"
  if ! [ -d "$repo" ]; then
    download_src
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

  local envname="$1"
  local version="$2"

  local go_root=""
  local go_path="$GLEN_ENV/$envname"
  local go_version="$version"
  local go_bin_path="$go_path/bin":"$GLEN_ROOT/$version/bin"
  local ps1="($envname:$go_version)\$PS1"

  cat <<ACTIVATE_SCRIPT
#!/bin/sh

[ -f $GLEN_DIR/.glenrc ] && . $GLEN_DIR/.glenrc || true

export GOROOT="$go_root"
export GOPATH="$go_path"
export PS1="$ps1"
export PATH="$go_bin_path:\$PATH"

ACTIVATE_SCRIPT
}

glen_available () {
  download_src_if_not_exist

  local tags=(`listup_src_tags`)
  for tag in "${tags[@]}"; do
    echo "$tag"
  done
}

glen_list () {
  download_src_if_not_exist
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
  download_src_if_not_exist

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
    return $ret
  fi
  echo "successfully installed: $version" >&2
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

build () {
  local version="$1"
  local godir="$2"
  local repo="$GLEN_SRC"
  local datetime=`date +"%Y%m%d%H%M%S"`
  local logfile="$GLEN_BUILDLOG/$version-$datetime.log"

  cd "$repo"
  if eval "git checkout "$version" &> $logfile"; then
    cd src
    rm -rf pkg && rm -rf bin
    if ./all.bash 2>&1 | tee -a "$logfile"; then
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
    echo "failed with code=$ret" >&2
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
    error "usage: glen mkenv <envname> <version>"
    die "envname required."
  fi
  if [ -z "$version" ]; then
    error "usage: glen mkenv <envname> <version>"
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

  local env="$GLEN_ENV/$envname"
  ensure_dir "$env"

	local script=`output_activate_script $envname $version`
 	echo "$script" > "$env/activate.sh"
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
  glen_workon "$@"
}

glen_workon () {

  local envname="$1"
  if [ -z "$envname" ]; then
    die "envname required."
  fi

  if [ "$envname" == "$GLEN_ENV_NAME" ]; then
    error "already workon $envname" >&2
    exit 0
  fi

  local activate_script="$GLEN_ENV/$envname/activate.sh"
  if [ ! -f "$activate_script" ]; then
    die "env not found. : $envname"
  fi

  type deactivate >/dev/null 2>&1
  if [ $? -eq 0 ]; then
      deactivate
      unset -f deactivate >/dev/null 2>&1
  fi

  GLEN_ENV_NAME=$envname \
    "$SHELL" --rcfile "$activate_script"

  exit_code=$?
  hash -r
  return $exit_code
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
    version | list | available | update | install | uninstall | \
    env | workon )
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
  echo "0.1.0"
}

glen_help () {
  cat <<EOF

Usage: glen <cmd>

Commands:

version                         Print glen version
help                            Output help text
install <version>               Install the version passed (ex: go1.4.2)
uninstall <version>             Delete the install for <version>
list                            List installed versions
available                       List available versions (tags)
env list                        List environments
env create <envname> <version>  Create environment
env delete <envname>            Delete environment
workon <envname>                Activate environment

EOF
}

main "$@"
