# Claude Code + Cloudera AI Inference

Run [Claude Code](https://code.claude.com/docs/en/quickstart) against a model on [Cloudera AI Inference](https://docs.cloudera.com/machine-learning/cloud/ai-inference/topics/ml-caii-use-caii.html).

Claude Code expects Anthropic's API. CAI Inference exposes OpenAI's API. A local LiteLLM proxy translates between them.

```
claude-cai  →  LiteLLM (localhost:4000)  →  your CAI endpoint
```

## Why use AI-assisted coding on Cloudera AI Inference?

Pairing agentic coding tools like Claude Code with Cloudera AI Inference gives you the speed of AI-assisted development—auto-generate, debug, and iterate in-line—without sending code or data to a third-party API. Models run where your data already lives (on-prem, cloud, or air-gapped), so there is zero data egress, native access to enterprise data, and no time lost on API stitching or environment friction. You keep full control over which models you run (open-weight, proprietary, or hybrid), how inference is routed, and how access is governed to meet regulatory requirements. On tokenomics, CAI Inference eliminates the per-token SaaS tax: you shift from unpredictable API spend to predictable infrastructure cost, run high-volume agent, RAG, and batch workloads without cost explosion, and optimize GPU reuse through autoscaling—turning weeks of AI application delivery into hours while you own your data and your AI.

---

## 1. Get this repo

**Clone:**

```bash
git clone https://github.com/kevinbtalbert/Claude-CLI-with-CAI-Inference.git
cd Claude-CLI-with-CAI-Inference
```

**Or download:** open the [GitHub repo](https://github.com/kevinbtalbert/Claude-CLI-with-CAI-Inference), click **Code → Download ZIP**, unzip, and `cd` into the folder.

---

## 2. Install (one time)

**Requires:** Python 3.9+, curl, network access to your CAI endpoint.

```bash
./scripts/install-cai-claude.sh
```

The installer will:

1. Check Python and curl (fail fast if missing)
2. Create `~/.claude/cai-inference/venv` and install LiteLLM
3. Install Claude Code if you don't have it
4. Ask for your **endpoint URL** and **JWT** (see below)
5. Install the `claude-cai` command to `~/.local/bin`

On reload, press **Enter** to keep saved URL and token.

---

## 3. Get your URL and token

**URL** — copy from your model's **Code Sample** tab in the Cloudera console. Either format works:

```text
.../endpoints/<name>/openai/v1    ← vLLM models (e.g. Hermes)
.../endpoints/<name>/v1             ← NIM models (e.g. Nemotron)
```

**Token** — a [Cloudera JWT](https://docs.cloudera.com/machine-learning/cloud/ai-inference/topics/ml-caii-authentication.html):

- **Generate JWT Token** on the Model Endpoint page (quick test), or
- **Knox JWT** from Data Lake → Token Integration (recommended for daily use)

Paste the token and press **Enter**. It will be visible while pasting (this avoids a known terminal hang with long JWTs). Alternatively: `export CAI_CDP_TOKEN='...'` before running the installer.

---

## 4. Run Claude Code (every session)

```bash
claude-cai
```

Other commands:

```bash
claude-cai -p "explain this repo"   # one-shot prompt
claude-cai --reconfigure             # change URL or token
claude-cai --stop-proxy              # stop background LiteLLM
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `command not found: claude-cai` | Add `~/.local/bin` to your PATH, or re-run the installer |
| `401 Unauthorized` | JWT expired — generate a new one and run `claude-cai --reconfigure` |
| Paste JWT then nothing happens | Paste token, press **Enter**, wait for "Checking endpoint..." — or set `CAI_CDP_TOKEN` in the environment |
| Chat works, tools don't | Model needs tool calling enabled on the endpoint (vLLM: `--enable-auto-tool-choice --tool-call-parser <parser>`) |
| `Not installed` | Run `./scripts/install-cai-claude.sh` |

---

## References

- [CAI Inference overview](https://docs.cloudera.com/machine-learning/cloud/ai-inference/topics/ml-caii-use-caii.html)
- [CAI Authentication](https://docs.cloudera.com/machine-learning/cloud/ai-inference/topics/ml-caii-authentication.html)
- [LiteLLM + Claude Code](https://docs.litellm.ai/docs/tutorials/claude_non_anthropic_models)
