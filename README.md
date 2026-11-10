# 🛡️ Zynx_integrity

<p align="center">
  <b>Lightweight Bash File Integrity Monitor</b><br>
  Detect unexpected changes to important Linux binaries and configuration files.
</p>

<p align="center">
  <code>BASH</code> · <code>SHA-256</code> · <code>FIM</code> · <code>Linux</code>
</p>

---

## ✨ What is Zynx_integrity?

**Zynx_integrity** is a lightweight File Integrity Monitoring (FIM) tool written entirely in Bash.

It creates a trusted baseline containing the SHA-256 hash of each file in selected system directories. On later scans, it hashes those files again and compares the results with the baseline.

It reports:

| Finding | Meaning |
|---|---|
| `CHANGED` | A file exists in both scans, but its SHA-256 hash differs |
| `REMOVED` | A file recorded in the baseline is no longer present |
| `NEW` | A file exists now but was not in the baseline |
| `CLEAN` | No differences or scan errors were detected |

The interface includes an interactive terminal menu, boxed status messages, a live elapsed-runtime display, and the **zynx** watermark.

## ⚙️ Features

- **SHA-256 verification** using `sha256sum`.
- **Directory discovery** using `find`.
- **Fast comparison** using `comm`, `sort`, and `awk`.
- **Unified difference generation** using `diff`.
- **Interactive Bash TUI** with simple numbered options.
- **Elapsed runtime** displayed in the top header.
- **No Python, Perl, Ruby, Node.js, or third-party Bash framework.**
- **Atomic baseline replacement**: a new baseline is installed only after scanning completes.
- **Restricted database permissions**: baseline file is created with mode `600`.
- **Non-zero findings are shown clearly** so changes can be investigated.

## 📁 Monitored locations

By default, the tool scans:

```text
/bin
/sbin
/usr/bin
/usr/sbin
/usr/local/bin
/etc
```

Only regular files are hashed. Directories that do not exist are skipped. On systems where `/bin` or `/sbin` is a symbolic link, `find` does not follow that link; the corresponding `/usr/...` directory is included separately on many modern Linux distributions.

## 📦 Requirements

- Linux
- Bash 4 or newer
- `find` (findutils)
- `sha256sum`, `sort`, `comm`, `diff`, `awk`, `cut`, `install`, `stat`, `du`, `wc` (normally provided by GNU coreutils / standard base utilities)

No package installation is normally required on Kali Linux, Debian, Ubuntu, or similar distributions.

## 🚀 Installation

Clone the repository:

```bash
git clone https://github.com/YOUR-USERNAME/Zynx_integrity.git
cd Zynx_integrity
```

Make the script executable:

```bash
chmod +x Zynx_integrity.sh
```

Run the TUI:

```bash
sudo ./Zynx_integrity.sh
```

> Run as root for the most complete scan. Without root, some protected files may be unreadable and will be reported as scan/read errors.

## 🧭 How to use

### 1. Create the initial baseline

Run:

```bash
sudo ./Zynx_integrity.sh --init
```

Or launch the TUI and select **1 — Create / rebuild trusted baseline**.

The tool hashes the files it can read and saves the baseline at:

```text
/var/lib/zynx_integrity/baseline.tsv
```

The database directory is restricted and the baseline file is created with permissions `600`.

**Important:** Create this baseline only when you believe the system is clean. A baseline made after a compromise may record malicious files as trusted.

### 2. Run an integrity check

```bash
sudo ./Zynx_integrity.sh --check
```

Or launch the TUI and select **2 — Run integrity check**.

The tool compares the current file hashes and paths with the saved baseline.

Example output:

```text
INTEGRITY ALERT

Changed files (1):
  [CHANGED] /usr/bin/example
    old: 0123456789abcdef...
    new: fedcba9876543210...

Removed files (1):
  [REMOVED] /etc/example.conf

New files (1):
  [NEW] /usr/local/bin/unexpected-tool
```

A detected change is an alert for investigation, not proof of malware. Legitimate package upgrades and configuration changes also modify files.

### 3. Open the interactive TUI

```bash
sudo ./Zynx_integrity.sh
```

Menu:

```text
[1] Create / rebuild trusted baseline
[2] Run integrity check
[3] Show monitored directories
[4] Baseline database information
[5] Exit
```

### 4. Use a custom database location

Set `ZYNX_DB` before launching the tool:

```bash
sudo ZYNX_DB=/root/zynx-baseline.tsv ./Zynx_integrity.sh --init
sudo ZYNX_DB=/root/zynx-baseline.tsv ./Zynx_integrity.sh --check
```

The same database path must be used for every check.

## 🔐 Security notes

A FIM tool is only as trustworthy as its baseline and execution environment.

1. **Protect the baseline.** A privileged attacker who can alter both the monitored files and the database can hide tampering. Store a copy off-host or on read-only/otherwise protected storage for stronger assurance.
2. **Use a known-clean baseline.** Prefer creating it immediately after a trusted OS installation or verified maintenance.
3. **Review expected updates.** Package upgrades, patches, and administrator changes legitimately change hashes. Rebuild the baseline only after verifying those changes.
4. **Run checks regularly.** This script performs a scan when you invoke it; it is not a background real-time monitor.
5. **Treat errors seriously.** If files could not be read or directories could not be scanned, a clean result cannot be guaranteed.
6. **Understand coverage.** The default directory list is intentionally focused. It does not monitor every filesystem location, mounted volume, user home directory, or kernel/runtime memory.

### Filename limitation

The manifest is a human-readable TSV file. Filenames containing a tab or newline are skipped because those characters cannot be represented unambiguously in this format. Ordinary Linux filenames, including spaces, are supported.

## ⚡ Performance

- Uses SHA-256 hashing directly; file contents must be read to verify them.
- Uses NUL-delimited discovery from `find`, avoiding common whitespace/path-splitting bugs.
- Uses sorted manifests and `comm` for efficient path comparison.
- Keeps temporary scan data in a private temporary directory and removes it on exit.

Scan time depends mainly on the number and total size of files, storage speed, and system load. Hashing large files is I/O-bound; no integrity monitor can verify their contents without reading them.

## 🧪 Quick test (safe lab)

You can test the concept in a disposable Linux VM:

1. Create a baseline.
2. Modify a test file inside one of the monitored directories only in a disposable VM (do not modify production system binaries).
3. Run the check again.
4. Observe the `CHANGED` result.
5. Restore the file or rebuild the baseline after verifying the system.

## 🧰 Commands

| Command | Action |
|---|---|
| `./Zynx_integrity.sh` | Launch TUI |
| `./Zynx_integrity.sh --init` | Create or rebuild baseline |
| `./Zynx_integrity.sh --check` | Run integrity check |
| `./Zynx_integrity.sh --show-dirs` | Show monitored directories |
| `./Zynx_integrity.sh --help` | Show help |

## 📜 License

Choose a license before publishing (MIT is a common option for small open-source tools).

---

<p align="center">
  <b>zynx</b> · Keep an eye on what matters.
</p>
