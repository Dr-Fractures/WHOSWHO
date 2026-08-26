# 
# Who's Who

Interactive Bash wrapper around `nmap` that auto-detects your default gateway/subnet, walks you through each recon stage with a yes/no prompt, shows the exact command before it runs, and saves indexed, timestamped output for use with other tools.

Named after the Zombies Gobblegum that reveals a downed player's identity — fitting, since this tool is all about identifying hosts, ports, services, and OSes on a network.

## Features

- **Auto-detects** default interface, gateway, and local CIDR (`ip route` / `ip addr`), with the option to override
- **Six guided scan stages**: ping sweep, fast top-100 ports, service/version detection, OS detection, optional full 65535-port scan, default NSE script scan
- **Prompts before every stage** and displays the exact `nmap` command for educational transparency
- **Live-host chaining**: results from the ping sweep feed directly into later stages
- **Indexed, timestamped output**: each run creates `scan_results/session_<timestamp>/` with files like `01_host_discovery.txt`, `02_fast_port_scan.txt`, plus a `00_index.txt` correlating step → label → command → filepath for easy parsing by other scripts
- **Readable terminal summaries**: after each stage, a colorized recap (hosts found, open ports/services in a table, OS guesses) prints alongside the raw output

## Requirements

- Bash
- `nmap` (`sudo apt install nmap`)
- Linux with `ip` (iproute2) for auto-detection
- Root/`sudo` recommended for SYN scans (`-sS`) and OS detection (`-O`); without it, scans fall back to TCP connect scans

## Install

```bash
git clone https://github.com/AmpedGH/whoswho.git
cd whoswho
./install.sh
```

This symlinks `whoswho.sh` to `/usr/local/bin/whoswho` so it can be run from anywhere.

## Usage

```bash
sudo whoswho
```

(`sudo` recommended for full scan capability; it will still run without it, with reduced functionality.)

Follow the prompts. Output is saved under `./scan_results/session_<timestamp>/` in the directory you ran the command from.

## Uninstall

```bash
./uninstall.sh
```

## Disclaimer

Only scan networks and hosts you own or have explicit authorization to test. Unauthorized scanning may violate laws or acceptable-use policies.

## Related tools

Part of a wireless/network recon toolkit alongside `doubletap`, `probe-hunter`, `wifi-scan`, and `wifi-sniff` — Bash scripts wrapping standard security tools, symlinked to `/usr/local/bin/`, each with its own repo.

