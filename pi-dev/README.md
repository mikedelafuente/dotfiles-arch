# pi-dev

Working area for customizing the `pi` coding agent (https://pi.dev).

## Current state

`scripts/setup-pi.sh` installs the stock published package
(`@earendil-works/pi-coding-agent` via npm, per https://pi.dev/docs/latest).
Nothing in this folder is wired into setup yet — it's the landing spot for a
fork/patches once there's something specific to customize.

## Intent

Once customization needs are known, this folder holds the fork or patch set
and whatever build step produces a `pi` binary from it, and `setup-pi.sh`
switches from the npm install to building from here.

## TODO

- [ ] Decide fork location (submodule vs vendored clone) and record it here
- [ ] Document the build command once known
- [ ] Point `setup-pi.sh` at the local build instead of the npm package
