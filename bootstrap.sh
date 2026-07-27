#!/bin/bash
set -euo pipefail
umask 022

VOLUME_NAME="Data"
VOLUME_PATH="/Volumes/${VOLUME_NAME}"
EXPECTED_FS="Case-sensitive APFS"
EDITABLE_PARENT="${VOLUME_PATH}/natronite"
EDITABLE_CLONE="${EDITABLE_PARENT}/droidstack"
TRUSTED_PARENT="${HOME}/.local/share"
TRUSTED_CLONE="${TRUSTED_PARENT}/droidstack"
REPO_URL="https://github.com/natronite/droidstack.git"
DROIDSTACK_BRANCH="stable"
SETUP_SCRIPT="setup.sh"
GITHUB_TOKEN=""
ASKPASS_SCRIPT=""

function cleanup() {
  if [ -n "$ASKPASS_SCRIPT" ] && [ -e "$ASKPASS_SCRIPT" ]; then
    rm -f "$ASKPASS_SCRIPT"
  fi
  unset GITHUB_TOKEN
}

trap cleanup EXIT

echo "Bootstrapping droidstack environment"

if /usr/bin/id -u aiagent >/dev/null 2>&1; then
  cat >&2 <<'EOF'
❌ Ignition is only for bootstrapping a machine before aiagent exists.

Use the protected droidstack launcher for subsequent setup runs:
  /usr/local/bin/droidstack-setup
EOF
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "📦 Installing Command Line Tools..."
  xcode-select --install
  echo "ℹ️  Please complete the installation, then re-run this script."
  exit 1
fi

function wait_for_volume() {
  local count=0
  tput civis  # hide cursor
  trap "tput cnorm; exit" INT TERM  # restore cursor on interrupt

  while [ ! -d "$VOLUME_PATH" ]; do
    if (( count % 5 == 0 )); then
      echo -ne "\r                                                                                          "
      echo -ne "\rWaiting for $VOLUME_PATH to be created and mounted (case-sensitive APFS)"
    else
      echo -ne "."
    fi
    sleep 1
    ((count++))
  done

  tput cnorm  # restore cursor
  echo -e "✅ $VOLUME_PATH detected.                                                                              "
}

function verify_case_sensitivity() {
  local fs_personality
  fs_personality=$(diskutil info "$VOLUME_PATH" | awk -F': ' '/File System Personality/ {gsub(/^ +/, "", $2); print $2}')

  if [ "$fs_personality" != "$EXPECTED_FS" ]; then
    echo "$VOLUME_PATH is not case-sensitive (found: '$fs_personality')"
    echo "Please erase and recreate the volume as 'APFS (Case-sensitive)' and try again."
    exit 1
  fi

  echo "✅ $VOLUME_PATH is case-sensitive."
}

function configure_git_credentials() {
  if [ -n "$ASKPASS_SCRIPT" ]; then
    return
  fi

  echo -ne "\a"
  read -rsp "🔑 GitHub Token: " GITHUB_TOKEN
  echo

  ASKPASS_SCRIPT=$(mktemp)
  chmod 0700 "$ASKPASS_SCRIPT"
  printf '%s\n' \
    '#!/bin/sh' \
    'case "$1" in' \
    '  *Username*) printf "%s\n" "$GIT_USERNAME" ;;' \
    '  *) printf "%s\n" "$GITHUB_TOKEN" ;;' \
    'esac' >"$ASKPASS_SCRIPT"
}

function clone_repo_securely() {
  local clone_dir="$1"
  local description="$2"

  if [ -d "$clone_dir/.git" ]; then
    echo "ℹ️ $description already exists at $clone_dir"
    return
  fi

  if [ -e "$clone_dir" ]; then
    echo "❌ $clone_dir exists but is not a Git checkout." >&2
    return 1
  fi

  configure_git_credentials
  mkdir -p "$(dirname "$clone_dir")"
  echo "📥 Creating $description at $clone_dir..."
  GIT_USERNAME=natronite \
    GITHUB_TOKEN="$GITHUB_TOKEN" \
    GIT_ASKPASS="$ASKPASS_SCRIPT" \
    GIT_TERMINAL_PROMPT=0 \
    git clone --branch "$DROIDSTACK_BRANCH" "$REPO_URL" "$clone_dir"
}

wait_for_volume
verify_case_sensitivity
clone_repo_securely "$EDITABLE_CLONE" "editable Codex checkout"
clone_repo_securely "$TRUSTED_CLONE" "trusted setup checkout"
chmod go-w "$HOME" "$HOME/.local" "$TRUSTED_PARENT"
chmod -R go-w "$TRUSTED_CLONE"

echo "✅ Bootstrap complete."
echo "ℹ️  Codex works in: $EDITABLE_CLONE"
echo "ℹ️  Setup runs from: $TRUSTED_CLONE"

# Run setup only from the trusted checkout.
if [ -f "$TRUSTED_CLONE/$SETUP_SCRIPT" ]; then
  echo "🚀 Running setup script: $SETUP_SCRIPT"
  /bin/zsh "$TRUSTED_CLONE/$SETUP_SCRIPT"
else
  echo "⚠️ No setup script found at: $TRUSTED_CLONE/$SETUP_SCRIPT"
fi
