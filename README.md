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
- Hugging Face access through `HF_TOKEN`
- `git`, `curl`, `python3`, and `sudo`
- An interactive terminal for sudo prompts

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

### Local vLLM Inference

This demo now defaults to local vLLM instead of Ollama. Recent NemoClaw builds
validate that local inference returns structured `tool_calls`; Ollama can return
tool calls as plain assistant text, which blocks onboarding for tool-heavy
OpenClaw demos.

The onboarding script starts `vllm/vllm-openai:v0.20.0` on port `8000` with
NVIDIA Nemotron 3 Nano FP8 and the parser flags required for structured tool
calls. First start downloads the model from Hugging Face and can take a while.

Make sure your Hugging Face token is available:

```bash
test -n "${HF_TOKEN:-}" && echo "HF_TOKEN is set"
```

If model download fails with an authorization or terms error, accept the model
terms on Hugging Face for `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8`, then run
the onboarding command again.

For the cleanest Quick Start, do not keep another NemoClaw sandbox running on the same gateway. If you already have a sandbox from another demo, either use it with `./scripts/start-demo.sh --sandbox <name>` or destroy it before onboarding `pst-agent`.

## Quick Start

```bash
git clone https://github.com/nv-drollins/nemoclaw-pst.git
cd nemoclaw-pst

./scripts/onboard-nemoclaw.sh
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
./scripts/onboard-nemoclaw.sh
```

This starts or reuses a local vLLM container, checks NVIDIA CDI GPU passthrough,
and runs the official NemoClaw installer in non-interactive mode. NemoClaw is
configured with `NEMOCLAW_PROVIDER=vllm` and the local model server at
`http://127.0.0.1:8000/v1`.

The wrapper also sets `NEMOCLAW_SANDBOX_READY_TIMEOUT=600` by default because first-run sandbox image upload and startup can take longer than NemoClaw's default 180-second readiness window on a fresh DGX Spark.

#### NemoClaw onboarding variables

`scripts/onboard-nemoclaw.sh` is a vLLM-focused wrapper. It always calls the
official NemoClaw installer with `--non-interactive`,
`--yes-i-accept-third-party-software`, and `--fresh`.

| Variable | Default | Available options / examples | Purpose |
|---|---:|---|---|
| `PST_VLLM_MODEL_ID` | `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8` | Any compatible Hugging Face model ID | Selects the model vLLM serves. |
| `PST_VLLM_SERVED_MODEL_NAME` | `model` | Any OpenAI-compatible served model name | Selects the model name NemoClaw/OpenClaw uses. |
| `PST_VLLM_PORT` | `8000` | TCP port | Host port for local vLLM. |
| `PST_VLLM_MAX_MODEL_LEN` | `65536` | Token count | vLLM context length. Increase if your PST workload needs more context. |
| `NEMOCLAW_SANDBOX_NAME` | `pst-agent` | Any valid sandbox name, for example `my-pst-agent` | Names the NemoClaw sandbox. Use a unique name to avoid replacing another sandbox. |
| `NEMOCLAW_POLICY_TIER` | `balanced` | `restricted`, `balanced`, `open` | Selects NemoClaw's baseline policy tier during onboarding. |
| `NEMOCLAW_INSTALL_REF` | unset (latest) | `v0.0.38`, `v0.0.43`, or another published installer ref | Pins the official NemoClaw installer for repeatable demo testing. Leave unset for latest. |
| `NEMOCLAW_LOCAL_INFERENCE_TIMEOUT` | `600` | Seconds, for example `900` | Wait time for local inference validation and model warm-up. |
| `NEMOCLAW_SANDBOX_READY_TIMEOUT` | `600` | Seconds, for example `900` | Wait time for first-run sandbox image upload and startup. |

| Setting | Source | Available options | Notes |
|---|---|---|---|
| `--fresh` | Official NemoClaw installer | Always passed by this demo wrapper | Creates a fresh demo-oriented NemoClaw/OpenShell setup. |
| `--no-fresh` | Not supported by this demo wrapper | N/A | The vanilla repo has this convenience option if you need to preserve an existing setup. |
| `NEMOCLAW_PROVIDER` | Demo wrapper | `vllm`, `ollama` | Default is `vllm`. The legacy Ollama path is kept only as an explicit fallback. |

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
./scripts/start-vllm.sh
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

This script handles both current Docker-driver sandboxes and older gateway/pod sandboxes. In Docker-driver mode the dashboard is already exposed through the sandbox host network; in older gateway mode the script repairs the common stale-forward case before it prints the URL. Without `--show-token`, the script prints the dashboard URL and the command to retrieve the token.

The dashboard is intentionally bound to localhost on the machine running the demo. If your browser is on another machine, first run the SSH tunnel command printed by the script, for example:

```bash
ssh -N -L 18789:127.0.0.1:18789 nvidia@<spark-ip>
```

Then open this URL on your browser machine:

```text
http://127.0.0.1:18789/
```

## Stop And Restart

Stop the PST service, dashboard forward, and repo-managed vLLM container:

```bash
./scripts/stop-demo.sh
```

Set `PST_KEEP_VLLM=1` if you want to keep the vLLM container warm between demo
runs:

```bash
PST_KEEP_VLLM=1 ./scripts/stop-demo.sh
```

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

### Version pinning and diagnostics

Leave `NEMOCLAW_INSTALL_REF` unset for the current NemoClaw installer. To compare against the older lane that previously worked for some demos, prefix onboarding:

```bash
NEMOCLAW_INSTALL_REF=v0.0.38 ./scripts/onboard-nemoclaw.sh
```

The PST demo has also been tested with `v0.0.38` as a comparison point. That install path completed, but the remaining TUI/agent connection issue still appeared in the OpenClaw gateway path, so use the pin for reproduction and debugging rather than as the default fix.

Check the installed stack before debugging a sandbox issue:

```bash
nemoclaw --version
openshell --version
nemoclaw pst-agent status
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl http://127.0.0.1:8000/v1/models
```

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
