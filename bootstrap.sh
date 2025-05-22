#!/bin/bash
set -euo pipefail

VOLUME_NAME="Data"
VOLUME_PATH="/Volumes/${VOLUME_NAME}"
EXPECTED_FS="Case-sensitive APFS"
USER_DIR="${VOLUME_PATH}/natronite"
CLONE_DIR="${USER_DIR}/droidstack"
REPO_URL="https://github.com/natronite/droidstack.git"
SETUP_SCRIPT="setup.sh"
GITHUB_TOKEN=""

echo "Bootstrapping droidstack environment"

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

function clone_repo_securely() {
  if [ -d "$CLONE_DIR/.git" ]; then
    echo "ℹ️ Repo already cloned at $CLONE_DIR"
    return
  fi

  echo -ne "\a"
  read -rsp "🔑 GitHub Token: " GITHUB_TOKEN
  
  echo "📁 Creating directory: $USER_DIR"
  mkdir -p "$USER_DIR"

  echo "📥 Cloning $REPO_URL using secure token handling..."

  local askpass_script
  askpass_script=$(mktemp)

  echo -e "#!/bin/sh\necho \"$GITHUB_TOKEN\"" > "$askpass_script"
  chmod +x "$askpass_script"

  GIT_USERNAME=natronite GIT_ASKPASS="$askpass_script" git clone "$REPO_URL" "$CLONE_DIR"

  rm -f "$askpass_script"
  unset GITHUB_TOKEN
}

wait_for_volume
verify_case_sensitivity
clone_repo_securely

echo "✅ Bootstrap complete."

# Step 4: Run setup script if present
if [ -f "$CLONE_DIR/$SETUP_SCRIPT" ]; then
  echo "🚀 Running setup script: $SETUP_SCRIPT"
  GITHUB_TOKEN="$GITHUB_TOKEN" bash "$CLONE_DIR/$SETUP_SCRIPT"
else
  echo "⚠️ No setup script found at: $CLONE_DIR/$SETUP_SCRIPT"
fi
