#!/usr/bin/env zsh

set -eu

function error() {
  echo "[$(date "+%Y-%m-%dT%H:%M:%S%z")]: $*" >&2
}

function log() {
  printf '[bootstrap] %s\n' "$*" >&2
}

function install_xcode_clt() {
  if [ "$(uname -s)" = "Darwin" ]; then
    log "Detected macOS."
    
    # Check if Xcode Command Line Tools are already installed
    if xcode-select -p >/dev/null 2>&1; then
      log "Xcode Command Line Tools are already installed."
    else
      log "Trigger Xcode Command Line Tools installation."
      
      xcode-select --install

      log "[!] Please switch to the installer window and follow the prompts."
      log "... waiting for completion ..."
      until xcode-select -p >/dev/null 2>&1; do
        sleep 2
      done

      log "Xcode Command Line Tools installed successfully!"
    fi
  fi
}

# Look up `brew` in standard locations and eval `brew shellenv`
# in order to initialize PATH/FPATH/MANPATH in the current 
# script's environment.
function lookup_brew_and_add_to_path() {
  log "Look up `brew` in standard locations"

  if ! command -v brew >/dev/null 2>&1; then
    for brew_prefix in \
      "/opt/homebrew/bin" \
      "/usr/local/bin" \
      "/home/linuxbrew/.linuxbrew/bin"; do
      
      if [ -f "$brew_prefix/brew" ]; then
        log "Found `brew` in ${brew_prefix}."
        eval "$("$brew_prefix/brew" shellenv)"
        break
      fi
    done

    log "`brew` is not available."
  fi
}

# Installs Homebrew package manager on macOS and Linux if it is not already
# installed.
function install_homebrew() {
  local HOMEBREW_PKG_PATH="/tmp/homebrew.pkg"

  lookup_brew_and_add_to_path

  if command -v brew &> /dev/null; then
    log "Homebrew is already installed at $(where brew)."
  else
    log "Install Homebrew"
    local OS
    OS="$(uname -s)"

    case "${OS}" in
      "Darwin")
        # Install with `.pkg` installer, introduced in Homebrew 4.1.2. Since
        # Apple requires by default that all software installed via `installer`
        # is signed by a developer certificate issued by Apple, I consider this
        # method more secure than running the convenience script.
        log "Detected macOS, installing Homebrew with homebrew.pkg from Homebrew/brew..."

        release_json=$(
          curl \
            --fail \
            --location \
            --show-error \
            --silent \
            --header "Accept: application/vnd.github+json" \
            --header "X-GitHub-Api-Version: 2026-03-10" \
            https://api.github.com/repos/Homebrew/brew/releases/latest
        )
        release_asset_json=$(jq '.assets[] | select(.name | endswith ("pkg"))' <<< $release_json)
        asset_name=$(jq '.name' --raw-output <<< $release_asset_json)
        asset_browser_download_url=$(jq '.browser_download_url' --raw-output <<< $release_asset_json)
        log "Downloading ${asset_name}..."
        log "-> ${asset_browser_download_url}"

        curl --fail --location --show-error --silent --output "${HOMEBREW_PKG_PATH}" \
          "${asset_browser_download_url}"

        if (($? != 0)); then
          error "Failed to download Homebrew package installer from \
${asset_browser_download_url}."
          return 1
        fi

        if [[ -f "${HOMEBREW_PKG_PATH}" ]]; then
          log "Homebrew package installer downloaded to ${HOMEBREW_PKG_PATH}"
        else
          error "Homebrew package installer download failed. File was not \
found at ${HOMEBREW_PKG_PATH}."
          return 1
        fi

        log "Install Homebrew."
        sudo installer -package "${HOMEBREW_PKG_PATH}" -target "/"

        if command pkgutil --pkg-info "sh.brew.homebrew" &> /dev/null; then
          log "Homebrew installed successfully."
          rm -f "${HOMEBREW_PKG_PATH}"
        else
          error "Homebrew installation failed. Please confirm that the file at \
${HOMEBREW_PKG_PATH} is a valid package. You may download the .pkg file \
manually at https://github.com/homebrew/brew/releases/latest."
          return 1
        fi
        ;;

      "Linux")
        # Install with Bash shell script (https://github.com/Homebrew/install)
        log "Detected Linux, installing Homebrew with Bash shell script..."
        NONINTERACTIVE=1 /bin/bash -c "$(
          curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
        )"
        log "Installation script ran successfully."
        ;;

      *)
        error "Unexpected OS: ${OS}. Homebrew is only supported on macOS and Linux."
        return 1
        ;;
    esac

    lookup_brew_and_add_to_path

  fi
}

install_xcode_clt
install_homebrew
NONINTERACTIVE=1 HOMEBREW_NO_AUTO_UPDATE=1 brew install chezmoi
chezmoi init zagyi --apply
