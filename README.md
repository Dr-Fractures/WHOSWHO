# Who's Who

> **⚠️ Only scan networks and hosts you own or have explicit, written authorization to test.** Unauthorized scanning may violate the Computer Fraud and Abuse Act (or your local equivalent) and other laws. The script itself will prompt you to confirm authorization before running.

Interactive Bash wrapper around `nmap` that auto-detects your default gateway/subnet, walks you through each recon stage with a yes/no prompt, shows the exact command before it runs, and saves indexed, timestamped output for use with other tools.

Named after the Zombies Gobblegum that reveals a downed player's identity — fitting, since this tool is all about identifying hosts, ports, services, and OSes on a network.

## Features

- **Auto-detects** default interface, gateway, and local CIDR (`ip route` / `ip addr`), with the option to override
- **Six guided scan stages**: ping sweep, fast top-100 ports, service/version detection, OS detection, optional full 65535-port scan, default NSE script scan
- **Prompts before every stage** and displays the exact `nmap` command for educational transparency
- **Live-host chaining**: results from the ping sweep feed directly into later stages
- **Indexed, timestamped output**: each run creates `/tmp/whoswho_scans/session_<timestamp>/` with files like `01_host_discovery.txt`, `02_fast_port_scan.txt`, plus a `00_index.txt` correlating step → label → command → filepath for easy parsing by other scripts
- **Temporary by default**: results live under `/tmp`, so they're automatically cleared on reboot instead of piling up
- **Readable terminal summaries**: after each stage, a colorized recap (hosts found, open ports/services in a table, OS guesses) prints alongside the raw output

## Requirements

- Bash
- `nmap` (`sudo apt install nmap`)
- Linux with `ip` (iproute2) for auto-detection
- Root/`sudo` recommended for SYN scans (`-sS`) and OS detection (`-O`); without it, scans fall back to TCP connect scans

## Install

```bash
git clone https://github.com/Dr-Fractures/WHOSWHO.git
cd whoswho
./install.sh
```

This symlinks `whoswho.sh` to `/usr/local/bin/whoswho` so it can be run from anywhere.

## Usage

```bash
sudo whoswho
```

(`sudo` recommended for full scan capability; it will still run without it, with reduced functionality.)

Follow the prompts. Output is saved under `/tmp/whoswho_scans/session_<timestamp>/` and is cleared automatically on reboot. If you want scans to persist, edit `OUTDIR` near the top of `whoswho.sh`.

## Update

```bash
cd WHOSWHO
git checkout -- whoswho.sh   # discard any local edits first
git pull
chmod +x whoswho.sh install.sh
sudo ./install.sh
```

Pulls the latest script, restores executable permissions (git can drop these), and re-runs the installer so `/usr/local/bin/whoswho` points to the updated version.

## Uninstall

```bash
./install.sh --remove
```

## Disclaimer

Only scan networks and hosts you own or have explicit authorization to test. Unauthorized scanning may violate laws or acceptable-use policies.

## Related tools

Part of a wireless/network recon toolkit alongside `doubletap`, `probe-hunter`, `wifi-scan`, and `wifi-sniff` — Bash scripts wrapping standard security tools, symlinked to `/usr/local/bin/`, each with its own repo.
