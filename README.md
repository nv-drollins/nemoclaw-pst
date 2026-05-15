# NemoClaw PST Mail Demo

Self-contained NemoClaw/OpenClaw demo that lets an agent inspect a bundled sample Outlook `.pst` mailbox.

This version is built for DGX Spark / GB10 and other Linux ARM hosts. It does not use Outlook, Microsoft 365, Microsoft Graph, OAuth, or Aspose. Instead, it uses Ubuntu's small ARM-native `pst-utils` package and a local read-only PST service.

## Sudo Prompts

First-time setup may need sudo for host packages, Docker/NVIDIA toolkit configuration, or setup preflight checks. Passwordless sudo is not required, but install commands must run from an interactive terminal so sudo can prompt. When installing over SSH, use:

```bash
ssh -t nvidia@<spark-ip>
```

## What You Get

- A bundled sample mailbox at `data/Outlook.pst`
- A host-side PST service on port `9003`
- A sandbox policy that allows OpenClaw to reach only that local PST service
- An OpenClaw skill that uses `curl` to list folders, count emails, find latest emails, and search by sender or subject
- A small OpenClaw Node inference fix that trusts the sandbox CA instead of disabling TLS checks
- Start, stop, dashboard, token, smoke-test, and NemoClaw onboarding scripts

The sample PST is static, so every demo run uses the same mailbox contents:

```text
Outlook/Inbox: 6 emails
Outlook/Sent Items: 5 emails
Grand total: 11 emails
```

## Before You Begin

Use an Ubuntu host with:

- Docker
- NVIDIA Container Toolkit
- Ollama running on port `11434`
- `git`, `curl`, `python3`, and `sudo`
- Passwordless sudo for the user running the demo

### Enable Docker access without sudo

DGX Spark systems may not add the current user to the `docker` group by
default. If you skip this step, run Docker commands with `sudo`.

Open a new terminal and test Docker access:

```bash
docker ps
```

If you see a permission denied error while connecting to the Docker daemon
socket, add your user to the `docker` group:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

`newgrp docker` updates group membership for the current shell. You can also
log out and back in, then rerun `docker ps`.

### Configure Docker GPU runtime

DGX Spark systems may include the NVIDIA Container Toolkit out of the box, but
Docker still needs the NVIDIA runtime configured:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Optional verification:

```bash
sudo docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

### Install and expose Ollama

The NemoClaw sandbox must be able to reach the host Ollama server. Install
Ollama on the host, then configure the systemd service to listen on all
interfaces. **Important for DGX Spark / GB10: pin Ollama to `0.22.1`; newer
`0.23.x` builds have been observed to fall back to CPU-only execution on GB10.**

```bash
OLLAMA_VERSION=0.22.1
OLLAMA_ARCH="$(case "$(uname -m)" in aarch64|arm64) echo arm64 ;; x86_64|amd64) echo amd64 ;; *) uname -m ;; esac)"
curl -fL --show-error -o "/tmp/ollama-linux-${OLLAMA_ARCH}.tar.zst" \
  "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-${OLLAMA_ARCH}.tar.zst"
sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama 2>/dev/null || true
sudo usermod -a -G video,render ollama 2>/dev/null || true
sudo tar --zstd -xf "/tmp/ollama-linux-${OLLAMA_ARCH}.tar.zst" -C /usr/local
sudo chmod -R a+rX /usr/local/lib/ollama
sudo tee /etc/systemd/system/ollama.service >/dev/null <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=default.target
EOF

sudo mkdir -p /etc/systemd/system/ollama.service.d
printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0"\n' | sudo tee /etc/systemd/system/ollama.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

Verify Ollama is running:

```bash
curl http://0.0.0.0:11434
```

Expected response:

```text
Ollama is running
```

If it is not running, start it with:

```bash
sudo systemctl start ollama
```

Always start Ollama through systemd with `sudo systemctl restart ollama` or
`sudo systemctl start ollama`. Do not use `ollama serve &` for this demo. A
manually started Ollama process will not use the `OLLAMA_HOST=0.0.0.0`
systemd override, and the NemoClaw sandbox will not be able to reach the
inference server.

`OLLAMA_HOST=0.0.0.0` exposes Ollama on the host network. Use this on a trusted
local network, or apply host firewall rules appropriate for your environment.

Pull the local model first:

```bash
ollama pull nemotron-3-nano:30b
```

For the cleanest Quick Start, do not keep another NemoClaw sandbox running on the same gateway. If you already have a sandbox from another demo, either use it with `./scripts/start-demo.sh --sandbox <name>` or destroy it before onboarding `pst-agent`.

## Quick Start

```bash
git clone https://github.com/nv-drollins/nemoclaw-pst.git
cd nemoclaw-pst

NEMOCLAW_MODEL=nemotron-3-nano:30b ./scripts/onboard-nemoclaw.sh
./scripts/start-demo.sh
```

`start-demo.sh` installs `pst-utils` if needed, starts the PST service, applies sandbox policy, installs the PST skill, prepares OpenClaw's Node runtime for the local inference proxy, verifies the PST route from the host and sandbox, starts a verified localhost dashboard forward, and prints the OpenClaw dashboard URL and token.

Open the dashboard URL, paste the token when prompted, then try:

```text
What folders are in my PST mailbox, and how many emails are in each folder?
```

Other good prompts:

```text
Show me the latest 5 emails in the PST mailbox.
```

```text
Search the PST mailbox for emails with attachment in the subject.
```

```text
Find emails from Saqib in the sample mailbox.
```

## Running Against An Existing Sandbox

If you already have a NemoClaw sandbox, skip onboarding and pass its name:

```bash
./scripts/start-demo.sh --sandbox my-existing-sandbox
```

The default sandbox name for this repo is:

```bash
pst-agent
```

## What The Scripts Do

### Onboard NemoClaw

```bash
NEMOCLAW_MODEL=nemotron-3-nano:30b ./scripts/onboard-nemoclaw.sh
```

This uses the same hardened local-Ollama onboarding flow as the other GB10 demos. It checks NVIDIA CDI GPU passthrough, avoids the optional model-router pip path that can trigger Python environment errors, and redirects NemoClaw model pulls to the selected `NEMOCLAW_MODEL`.

The wrapper also sets `NEMOCLAW_SANDBOX_READY_TIMEOUT=600` by default because first-run sandbox image upload and startup can take longer than NemoClaw's default 180-second readiness window on a fresh DGX Spark.

#### NemoClaw onboarding variables

`scripts/onboard-nemoclaw.sh` is an Ollama-focused wrapper. It always calls the
official NemoClaw installer with `--non-interactive`,
`--yes-i-accept-third-party-software`, and `--fresh`.

| Variable | Default | Available options / examples | Purpose |
|---|---:|---|---|
| `NEMOCLAW_MODEL` | `nemotron-3-nano:30b` | Any Ollama model name from `ollama list`; examples: `nemotron-3-nano:30b`, `qwen3.6:35b` | Selects the local Ollama model NemoClaw/OpenClaw should use. |
| `NEMOCLAW_SANDBOX_NAME` | `pst-agent` | Any valid sandbox name, for example `my-pst-agent` | Names the NemoClaw sandbox. Use a unique name to avoid replacing another sandbox. |
| `NEMOCLAW_POLICY_TIER` | `balanced` | `restricted`, `balanced`, `open` | Selects NemoClaw's baseline policy tier during onboarding. |
| `NEMOCLAW_LOCAL_INFERENCE_TIMEOUT` | `300` | Seconds, for example `600` | Wait time for local inference validation and model warm-up. |
| `NEMOCLAW_SANDBOX_READY_TIMEOUT` | `600` | Seconds, for example `900` | Wait time for first-run sandbox image upload and startup. |
| `NEMOCLAW_OLLAMA_BIN` | auto-detected | Full path to `ollama` | Overrides which real Ollama binary the wrapper calls. |
| `NEMOCLAW_PIP3_BIN` | auto-detected | Full path to `pip3` | Overrides which real `pip3` binary the router-bypass shim delegates to. |

| Setting | Source | Available options | Notes |
|---|---|---|---|
| `--fresh` | Official NemoClaw installer | Always passed by this demo wrapper | Creates a fresh demo-oriented NemoClaw/OpenShell setup. |
| `--no-fresh` | Not supported by this demo wrapper | N/A | The vanilla repo has this convenience option if you need to preserve an existing setup. |
| `NEMOCLAW_PROVIDER` | Demo wrapper | `ollama` only | This PST demo is wired for local Ollama inference. |

| Script-set variable | Value | Notes |
|---|---:|---|
| `NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE` | `1` | Accepts the official installer's third-party software prompt for non-interactive setup. |
| `NEMOCLAW_NON_INTERACTIVE` | `1` | Keeps the installer in scripted mode. |

### Start The Demo

```bash
./scripts/start-demo.sh
```

The script runs:

```bash
./scripts/install-host-prereqs.sh
./scripts/start-pst-server.sh
./scripts/install-pst-skill.sh
./scripts/prepare-openclaw-node-inference.sh
./scripts/run-pst-smoke.sh
./scripts/show-openclaw-dashboard.sh --show-token
```

`prepare-openclaw-node-inference.sh` extracts the `inference.local` certificate chain from the OpenShell proxy, sets Node to use the sandbox proxy environment, and restarts the in-sandbox OpenClaw gateway with `NODE_EXTRA_CA_CERTS`. This avoids the `LLM request failed: network connection error` path without disabling TLS verification.

### Direct Smoke Checks

```bash
./scripts/run-pst-smoke.sh
```

Expected output includes folder counts and two messages matching subject `attachment`.

To also verify that a ready OpenClaw sandbox can reach the host PST service:

```bash
./scripts/run-pst-smoke.sh --sandbox pst-agent
```

### Show Dashboard URL And Token

```bash
./scripts/show-openclaw-dashboard.sh --show-token
```

This script repairs the common stale-forward case before it prints the URL. It verifies the dashboard inside the `pst-agent` pod, starts a Kubernetes port-forward inside the OpenShell gateway container, and exposes it through a localhost-only proxy on the host. Without `--show-token`, the script prints the dashboard URL and the command to retrieve the token.

The dashboard is intentionally bound to localhost on the machine running the demo. If your browser is on another machine, first run the SSH tunnel command printed by the script, for example:

```bash
ssh -N -L 18789:127.0.0.1:18789 nvidia@<spark-ip>
```

Then open this URL on your browser machine:

```text
http://127.0.0.1:18789/
```

## Stop And Restart

Stop the PST service:

```bash
./scripts/stop-demo.sh
```

This also stops the localhost dashboard forward created by `show-openclaw-dashboard.sh`.

Start it again:

```bash
./scripts/start-demo.sh
```

This does not destroy the NemoClaw sandbox.

## Using Your Own PST

The bundled sample is used by default. To use another PST file:

```bash
PST_PATH=/absolute/path/to/mailbox.pst ./scripts/start-demo.sh
```

Keep the file on the host. The sandbox never receives the PST file; it only calls the local read-only PST service.

## Why Not Aspose?

The upstream `outlook-pst-demo` uses `Aspose.Email-for-Python-via-NET`. That works on Linux x86_64, Windows x64, and macOS, but it does not currently publish a Linux ARM/aarch64 wheel. On DGX Spark / GB10, the dependency resolver reports no compatible wheel.

This repo uses `pst-utils` instead:

```bash
sudo apt-get install -y pst-utils
```

On Ubuntu ARM, that package is small and native. It provides `readpst`, which extracts the sample mailbox into mbox files that the local Python service reads with the standard library.

## Sample PST Attribution

The bundled `data/Outlook.pst` sample comes from the Aspose.Email Python examples repository:

```text
https://github.com/aspose-email/Aspose.Email-Python-Dotnet
```

The upstream license is included at:

```text
third_party/Aspose.Email-Python-Dotnet-LICENSE
```

Sample PST SHA256:

```text
d2770b20a777098dcaddba8eb1ffa9e1cc6dd75844fcd40769245fcd4ddec416
```

## Troubleshooting

Check the host service:

```bash
curl http://127.0.0.1:9003/health
curl http://127.0.0.1:9003/folders
```

Check logs:

```bash
tail -80 logs/pst-server.log
```

Check NemoClaw:

```bash
nemoclaw pst-agent status
```

If OpenClaw cannot reach the PST service, reapply the policy and reinstall the skill:

```bash
./scripts/install-pst-skill.sh pst-agent
```

If OpenClaw can reach the PST service but agent prompts fail with `LLM request failed: network connection error`, refresh the Node inference route:

```bash
./scripts/prepare-openclaw-node-inference.sh pst-agent
```
