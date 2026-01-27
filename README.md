# BtcLotoVpn

**Bitcoin Solo Miner + Multi-VPN for Raspberry Pi 4**

Turn your Raspberry Pi into a Bitcoin solo miner with remote Telegram control and multiple VPN options.

## Features

- **Bitcoin Solo Mining** - CPU mining with BFGMiner
- **Telegram Bot Control** - 45+ commands for remote management
- **Multi-VPN Support** - Tor, Mysterium, OpenVPN, Outline, Hysteria2, Xray
- **Web Dashboard** - Monitor mining status via browser
- **Wallet Alerts** - Get notified when you mine Bitcoin!

## Hardware Requirements

- Raspberry Pi 4 (4GB+ recommended)
- 1TB+ External HDD (for blockchain storage)
- Reliable internet connection
- MicroSD card (32GB+)

## Installation

### Option 1: Pre-built Image (Recommended)

Download the pre-configured image and flash it to your SD card:

1. **Download** the latest image from [Releases](https://github.com/micheldegeofroy/BtcLotoVpn/releases)
2. **Flash** to SD card using [Raspberry Pi Imager](https://www.raspberrypi.com/software/):
   - Click "Choose OS" → "Use custom" → Select the downloaded `.img.gz`
   - Click "Choose Storage" → Select your SD card
   - Click "Write"
3. **Boot** your Pi with the 1TB external HDD connected
4. **SSH** in: `ssh satoshi@<pi-ip>` (password: `nakamoto`)
5. **Configure**: Run `sudo btcconfig`

> **Default credentials:** `satoshi` / `nakamoto` — Change after first login!

### Option 2: Fresh Install

Install on existing Raspberry Pi OS:

```bash
curl -sSL https://raw.githubusercontent.com/micheldegeofroy/BtcLotoVpn/main/install.sh | sudo bash
```

Or clone and run:
```bash
git clone https://github.com/micheldegeofroy/BtcLotoVpn.git
cd BtcLotoVpn
sudo bash install.sh
```

## First Boot Setup

After installation, run the configuration wizard:
```bash
sudo btcconfig
```

You'll need:
- Bitcoin wallet address (for mining rewards)
- Telegram Bot Token (create at [@BotFather](https://t.me/BotFather))
- Telegram Chat ID (get from [@userinfobot](https://t.me/userinfobot))
- Blockonomics API key (optional, for balance alerts)

## Telegram Commands

| Category | Commands |
|----------|----------|
| **Status** | `/status` - System health overview |
| **Bitcoin** | `/startbtc` `/stopbtc` `/sync` `/chainstate` `/btc` |
| **Miner** | `/startminer` `/stopminer` |
| **Wallet** | `/wallet` `/mywallet` `/setwallet` `/makewallet` |
| **VPN** | `/toron` `/toroff` `/hyson` `/hysoff` ... |
| **System** | `/cpu` `/storage` `/reboot` `/htop` |

Use `/help` for the full command list.

## VPN Options

| VPN | Purpose |
|-----|---------|
| **Tor** | Anonymous Bitcoin traffic (Snowflake bridges) |
| **Mysterium** | Earn MYST tokens as a node provider |
| **Hysteria2** | Fast, censorship-resistant VPN |
| **OpenVPN** | Traditional VPN with .ovpn configs |
| **Outline** | Shadowsocks-based VPN |
| **Xray** | Advanced proxy protocol |

## Architecture

```
┌─────────────────────────────────────────┐
│           Raspberry Pi 4                │
├─────────────────────────────────────────┤
│  Telegram Bot ←→ User Commands          │
│       ↓                                 │
│  Bitcoin Core (via Tor network)         │
│  BFGMiner (CPU solo mining)             │
│       ↓                                 │
│  1TB HDD (/mnt/hdd/.bitcoin)            │
└─────────────────────────────────────────┘
```

## License

MIT License - See [LICENSE](LICENSE) for details.

## Disclaimer

Solo mining Bitcoin with a Raspberry Pi is unlikely to be profitable. This project is for educational purposes and the joy of participating in the Bitcoin network.

---

**Made with ☕ by [@micheldegeofroy](https://github.com/micheldegeofroy)**
