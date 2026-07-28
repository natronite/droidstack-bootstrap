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
SSH_REPO_URL="git@github.com:natronite/droidstack.git"
DROIDSTACK_BRANCH="stable"
SETUP_SCRIPT="setup.sh"
BOOTSTRAP_SSH_DIRECTORY=""
BOOTSTRAP_SSH_KEY=""
BOOTSTRAP_SSH_VERIFIED="false"

function cleanup() {
  case "$BOOTSTRAP_SSH_DIRECTORY" in
    /private/tmp/ignition-ssh.*)
      if [ -d "$BOOTSTRAP_SSH_DIRECTORY" ]; then
        rm -rf "$BOOTSTRAP_SSH_DIRECTORY"
      fi
      ;;
  esac
}

trap cleanup EXIT

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ssh-key)
      if [ "$#" -lt 2 ]; then
        echo "❌ --ssh-key requires a private-key path." >&2
        exit 64
      fi
      BOOTSTRAP_SSH_KEY="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bootstrap.sh [--ssh-key ABSOLUTE_PATH]

By default, Ignition recovers a resident SSH credential from a connected
FIDO2 security key. Use --ssh-key only for manual account-recovery fallback.
EOF
      exit
      ;;
    *)
      echo "❌ Unknown option: $1" >&2
      exit 64
      ;;
  esac
done

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

function git_with_bootstrap_key() {
  GIT_TERMINAL_PROMPT=0 \
    GIT_SSH_COMMAND="/usr/bin/ssh -i $BOOTSTRAP_SSH_KEY -o IdentitiesOnly=yes" \
    /usr/bin/git "$@"
}

function bootstrap_key_authenticates() {
  git_with_bootstrap_key \
    ls-remote "$SSH_REPO_URL" "refs/heads/$DROIDSTACK_BRANCH" \
    >/dev/null 2>&1
}

function ensure_bootstrap_ssh_key() {
  local candidate

  if [ "$BOOTSTRAP_SSH_VERIFIED" = "true" ]; then
    return
  fi

  if [ -n "$BOOTSTRAP_SSH_KEY" ]; then
    case "$BOOTSTRAP_SSH_KEY" in
      /*)
        ;;
      *)
        echo "❌ Bootstrap SSH-key path must be absolute." >&2
        exit 1
        ;;
    esac
    if [ ! -f "$BOOTSTRAP_SSH_KEY" ] || [ -L "$BOOTSTRAP_SSH_KEY" ]; then
      echo "❌ Bootstrap SSH key is not a regular file: $BOOTSTRAP_SSH_KEY" >&2
      exit 1
    fi
    case "$BOOTSTRAP_SSH_KEY" in
      *[!A-Za-z0-9_./-]*)
        echo "❌ Bootstrap SSH-key path contains unsupported characters." >&2
        exit 1
        ;;
    esac
  else
    BOOTSTRAP_SSH_DIRECTORY="$(mktemp -d /private/tmp/ignition-ssh.XXXXXX)"

    cat <<'EOF'
🔐 Insert the FIDO2 security key containing the resident GitHub SSH
   credential. You may be asked for its PIN and to touch or verify on the key.

   Verify any first-connection host-key prompt against:
   https://docs.github.com/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
EOF

    if ! (
      cd "$BOOTSTRAP_SSH_DIRECTORY"
      /usr/bin/ssh-keygen -K
    ); then
      cat >&2 <<'EOF'
❌ No resident SSH credential could be recovered.

If the security key is available, verify that its resident GitHub SSH key was
created and registered before this rebuild.

For manual recovery, regain GitHub access using a backup passkey, security key,
GitHub Mobile, or recovery code. Generate and upload a local SSH key,
then rerun:

  /bin/bash /tmp/ignition-bootstrap.sh \
    --ssh-key ~/.ssh/github_ed25519
EOF
      exit 1
    fi

    for candidate in "$BOOTSTRAP_SSH_DIRECTORY"/id_*; do
      [ -f "$candidate" ] || continue
      case "$candidate" in
        *.pub)
          continue
          ;;
      esac

      BOOTSTRAP_SSH_KEY="$candidate"
      if bootstrap_key_authenticates; then
        BOOTSTRAP_SSH_VERIFIED="true"
        break
      fi
      BOOTSTRAP_SSH_KEY=""
    done
  fi

  if [ -z "$BOOTSTRAP_SSH_KEY" ]; then
    echo "❌ No resident SSH credential can read the private Droidstack repository." >&2
    exit 1
  fi

  if [ "$BOOTSTRAP_SSH_VERIFIED" != "true" ] &&
    ! bootstrap_key_authenticates; then
    echo "❌ The selected SSH credential cannot read the private Droidstack repository." >&2
    exit 1
  fi

  BOOTSTRAP_SSH_VERIFIED="true"
  echo "✅ Bootstrap SSH credential authenticated."
}

function clone_repo_securely() {
  local clone_dir="$1"
  local description="$2"
  local require_remote_match="$3"
  local branch
  local current_commit
  local fetched_commit
  local origin

  if [ -d "$clone_dir/.git" ]; then
    echo "🔎 Validating existing $description at $clone_dir..."

    origin=$(/usr/bin/git -C "$clone_dir" remote get-url origin 2>/dev/null || true)
    if [ "$origin" != "$REPO_URL" ] &&
      [ "$origin" != "$SSH_REPO_URL" ] &&
      [ "$origin" != "git@github.com-natronite:natronite/droidstack.git" ]; then
      echo "❌ Unexpected origin for $description: $origin" >&2
      return 1
    fi

    branch=$(/usr/bin/git -C "$clone_dir" branch --show-current)
    if [ "$branch" != "$DROIDSTACK_BRANCH" ]; then
      echo "❌ $description must be on $DROIDSTACK_BRANCH, not $branch." >&2
      return 1
    fi

    if [ -n "$(/usr/bin/git -C "$clone_dir" status --porcelain --untracked-files=normal)" ]; then
      echo "❌ $description has uncommitted changes." >&2
      return 1
    fi

    if [ "$require_remote_match" = "true" ]; then
      ensure_bootstrap_ssh_key
      git_with_bootstrap_key \
        -C "$clone_dir" fetch "$SSH_REPO_URL" "$DROIDSTACK_BRANCH"

      current_commit=$(/usr/bin/git -C "$clone_dir" rev-parse HEAD)
      fetched_commit=$(/usr/bin/git -C "$clone_dir" rev-parse FETCH_HEAD)
      if [ "$current_commit" != "$fetched_commit" ]; then
        echo "❌ $description does not exactly match the fetched $DROIDSTACK_BRANCH branch." >&2
        return 1
      fi
    fi

    /usr/bin/git -C "$clone_dir" remote set-url origin "$REPO_URL"
    echo "✅ Existing $description is valid."
    return
  fi

  if [ -e "$clone_dir" ]; then
    echo "❌ $clone_dir exists but is not a Git checkout." >&2
    return 1
  fi

  ensure_bootstrap_ssh_key
  mkdir -p "$(dirname "$clone_dir")"
  echo "📥 Creating $description at $clone_dir..."
  git_with_bootstrap_key \
    clone --branch "$DROIDSTACK_BRANCH" "$SSH_REPO_URL" "$clone_dir"
  /usr/bin/git -C "$clone_dir" remote set-url origin "$REPO_URL"
}

wait_for_volume
verify_case_sensitivity
clone_repo_securely "$EDITABLE_CLONE" "editable Codex checkout" "false"
clone_repo_securely "$TRUSTED_CLONE" "trusted setup checkout" "true"
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
