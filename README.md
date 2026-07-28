# Ignition

Ignition bootstraps Droidstack on a new Mac. It creates separate editable and
trusted Droidstack checkouts, then runs setup from the trusted checkout.

## Bootstrap a new Mac

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

## Development

Ignition is the initial trust root for a new machine. A local checkout is not
inherently trusted or untrusted: that depends on how it was obtained, who can
modify it, and whether its exact contents were reviewed. The download command
above executes the current remote `bootstrap` branch; the review-first variant
makes that input visible before execution.

After bootstrap, ongoing workstation changes use Droidstack's separate
editable and trusted checkouts and the `droidstack-update` promotion flow.
