# Cloudflare Tunnel Wizard

A simple, formal, and interactive Bash wizard for installing and configuring **Cloudflare Tunnels** on Ubuntu. This script guides you step-by-step from installation to running a tunnel, making it easier than ever to expose local services securely via Cloudflare.

---

## 🔹 What is it

The **Cloudflare Tunnel Wizard** is a Bash script that:

* Automatically installs `cloudflared` on Ubuntu if not already installed.
* Guides you through logging in to your Cloudflare account.
* Collects your domain, subdomain (hostname), and local service port.
* Creates a Cloudflare Tunnel and DNS record.
* Sets up a systemd service for easy management.
* Provides clear instructions for manual or automated tunnel execution.

The script is designed to be **formal, simple, and interactive**, with colorized prompts to make each step clear.

---

## 🔹 How to Use

1. Clone this repository or download the script:

```bash
git clone https://github.com/yourusername/cloudflare-tunnel-wizard.git
cd cloudflare-tunnel-wizard
```

2. Make the script executable:

```bash
chmod +x cf-tunnel-wizard.sh
```

3. Run the wizard with sudo (required for systemd service setup):

```bash
sudo ./cf-tunnel-wizard.sh
```

4. Follow the interactive prompts to provide:

* Your Cloudflare domain
* Hostname (subdomain)
* Local port where your service runs
* Tunnel name (optional)

5. After completion, the wizard will:

* Create the tunnel
* Configure DNS routing
* Generate a configuration file
* Install and start a systemd service
* Show instructions for manual or service-based execution

---

## 🔹 Contributing

Contributions are welcome! If you want to help improve this script:

1. Fork this repository.
2. Create a new branch with your feature or fix.
3. Commit your changes with descriptive messages.
4. Open a pull request describing your changes.

Please ensure your code is readable, tested, and follows the style of the existing script.

---

## 🔹 Open Source

This project is **open-source** and free to use. You are welcome to:

* Modify it for your personal use
* Share it with others
* Contribute improvements back to the project

License: **MIT**
Feel free to check [LICENSE](LICENSE) for more details.

---

> Keep this script for future setups, adjustments, or new tunnel creation. It is designed to make managing Cloudflare Tunnels easier, faster, and user-friendly.
