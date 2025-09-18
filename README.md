# _Unofficial_ Komodo Binaries for Alpine
[![Latest Release](https://img.shields.io/github/v/release/nano9g/komodo-alpine?logo=alpinelinux)](https://github.com/nano9g/komodo-alpine/releases/latest)
[![Build Status](https://img.shields.io/github/actions/workflow/status/nano9g/komodo-alpine/build.yaml?logo=alpinelinux&label=build)](https://github.com/nano9g/komodo-alpine/actions/workflows/build.yaml)
[![Last Version Check](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.github.com%2Frepos%2Fnano9g%2Fkomodo-alpine%2Factions%2Fworkflows%2F189020361%2Fruns%3Fstatus%3Dcompleted%26per_page%3D1&query=%24.workflow_runs%5B0%5D.run_started_at&label=%F0%9F%A6%8E%20version%20checked&color=989499)](https://github.com/nano9g/komodo-alpine/actions/workflows/check.yaml)
[![Komodo Release](https://img.shields.io/github/v/release/moghtech/komodo?label=%F0%9F%A6%8E%20latest&color=rgba(160%2C%20170%2C%20160%2C%200.7)&labelColor=rgba(60%2C%2070%2C%2060%2C%200.7))](https://github.com/moghtech/komodo/releases/latest)

This repository builds automated ***unofficial*** [Komodo](https://komo.do) binaries for Alpine.

At this time, only Periphery is available. The `km` CLI could be added if there’s enough demand.

## Periphery Installation

### Script

The official Periphery install script doesn’t know about these binaries, nor can it deal with OpenRC services. You can use the script in this repository to install and it will do the right thing; musl+OpenRC on Alpine and running the official script for other platforms.

✴️ This requires root permissions, so apply `doas` or `sudo` after the pipe as needed.

```
curl -sSL https://raw.githubusercontent.com/nano9g/komodo-alpine/main/scripts/setup-periphery.sh | /bin/sh
```

<details>
<summary>

### Manual

</summary>

✴️ These steps must be performed with root permissions, so apply `doas` or `sudo` as needed.

1. Download the [latest release](https://github.com/nano9g/komodo-alpine/releases/latest) for your architecture and extract to `/usr/local/bin/periphery`
   ```
   curl -L "https://github.com/nano9g/komodo-alpine/releases/latest/download/periphery_musl_✴️YOUR-ARCHITECTURE-HERE✴️.tar.gz" -o periphery.tar.gz
   tar xf periphery.tar.gz
   mv periphery /usr/local/bin
   ```
3. Create the OpenRC service file at `/etc/init.d/periphery`
   ```
   #!/sbin/openrc-run

   description="Komodo Periphery Agent"
   command="/usr/local/bin/periphery"
   command_args="--config-path /etc/komodo/periphery.config.toml"
   command_background=true
   required_dirs=/etc/komodo
   pidfile=/run/periphery.pid
   output_log=/var/log/komodo.log
   output_err=/var/log/komodo.err
   ```
4. Create Periphery config file at `/etc/komodo/periphery.config.toml` ([template here](https://github.com/moghtech/komodo/blob/main/config/periphery.config.toml))
5. Make sure necessary files are executable, then enable and start the service:
   ```
   chmod +x /usr/local/bin/periphery /etc/init.d/periphery
   rc-update add periphery default
   service periphery restart
   ```

</details>

## More info

### How (and how often) are binaries produced?

Every 4 hours, [the latest Komodo release is checked](https://github.com/nano9g/komodo-alpine/actions/workflows/check.yaml). If a new one is avaialble, [builds are automatically compiled and uploaded](https://github.com/nano9g/komodo-alpine/actions/workflows/build.yaml) to a new release in this repo.

### Why is this needed?

Because [official Alpine binaries aren’t on the roadmap](https://github.com/moghtech/komodo/issues/479#issuecomment-2851612052).
