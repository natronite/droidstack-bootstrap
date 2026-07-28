# Ignition

Ignition bootstraps Droidstack on a new Mac. It creates separate editable and
trusted Droidstack checkouts, then runs setup from the trusted checkout.

## Bootstrap a new Mac

Ignition uses a resident SSH credential on a FIDO2 security key only to clone
the private Droidstack repository. Droidstack later creates separate local,
passphrase-protected GitHub and Bitbucket keys for normal work.

Before relying on Ignition for a rebuild:

1. Create a resident hardware-backed SSH key:

   ```sh
   ssh-keygen -t ed25519-sk \
     -O resident \
     -O verify-required \
     -O user=natronite-github-bootstrap \
     -C "natronite GitHub bootstrap" \
     -f ~/.ssh/id_ed25519_sk_github_bootstrap
   ```

   Leave the file passphrase empty. The security key's PIN and required
   fingerprint verification protect use of the credential.

2. Add its public key to the `natronite` GitHub account.
3. Keep an independent GitHub recovery method, preferably a second security
   key plus securely stored recovery codes.

Log in as `natronite`, open Terminal, and run this before creating the
`aiagent` account:

```sh
/usr/bin/curl --fail --show-error --silent --location \
  https://raw.githubusercontent.com/natronite/ignition/bootstrap/bootstrap.sh \
  --output /tmp/ignition-bootstrap.sh && \
  /bin/bash /tmp/ignition-bootstrap.sh
```

If macOS Command Line Tools are missing, the script starts their installer and
exits. Finish that installation, then run the same command again.

The command downloads the current `bootstrap` branch before executing it. To
review the downloaded script before execution, use these commands instead:

```sh
/usr/bin/curl --fail --show-error --silent --location \
  https://raw.githubusercontent.com/natronite/ignition/bootstrap/bootstrap.sh \
  --output /tmp/ignition-bootstrap.sh
/usr/bin/less /tmp/ignition-bootstrap.sh
/bin/bash /tmp/ignition-bootstrap.sh
```

After Ignition creates the checkouts, Droidstack setup may stop and ask for the
`aiagent` account to be created manually. Follow the displayed instructions,
then continue with the protected `droidstack-setup` command.

If the bootstrap security key is unavailable, regain GitHub access with a
backup passkey, security key, GitHub Mobile, or recovery code. Generate and
upload the normal per-Mac local SSH key:

```sh
/usr/bin/ssh-keygen -t ed25519 -a 100 \
  -C "natronite GitHub recovery" \
  -f ~/.ssh/github_ed25519
```

Then pass its path explicitly:

```sh
/bin/bash /tmp/ignition-bootstrap.sh \
  --ssh-key ~/.ssh/github_ed25519
```

Ignition never stores a GitHub token or copies a private key into either
Droidstack checkout. Recovered resident-key handles live in a temporary
directory that is removed when Ignition exits.

## Development

Ignition is the initial trust root for a new machine. A local checkout is not
inherently trusted or untrusted: that depends on how it was obtained, who can
modify it, and whether its exact contents were reviewed. The download command
above executes the current remote `bootstrap` branch; the review-first variant
makes that input visible before execution.

After bootstrap, ongoing workstation changes use Droidstack's separate
editable and trusted checkouts and the `droidstack-update` promotion flow.
