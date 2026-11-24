---
name: deploy-finetuned-model-as-cpu-ollama-on-proxmox-ct
description: "Serve a LoRA-fine-tuned small model as an always-on CPU Ollama OpenAI endpoint on a Proxmox LXC (merge, GGUF, P-core pin)."
---

Deploy a small fine-tune (e.g. Qwen2.5-7B + a LoRA) as an always-on, OpenAI-compatible CPU serve on a Proxmox LXC, off GPU boxes. Ordered steps and the walls that cost real time.

## 1. You MUST merge - Ollama dropped LoRA adapters
Ollama 0.40+ returns `Error: LoRA adapters are no longer supported` for a Modelfile `ADAPTER` directive. So you cannot ship base+adapter; you must merge the LoRA into the base and import a standalone GGUF.
- Merge where the GPU + base + adapter are (e.g. the 3090): `PeftModel.from_pretrained(base_fp16, adapter).merge_and_unload().save_pretrained(merged, max_shard_size="5GB")`. On GPU this is ~15s; free the GPU first (kill any serve holding VRAM - a 7B fp16 merge needs ~15GB).
- Convert with llama.cpp `convert_hf_to_gguf.py merged --outtype q8_0` (Python-only, NO quantize binary needed; clone llama.cpp, `pip install gguf sentencepiece protobuf`, set `PYTHONPATH=<clone>/gguf-py`). Q8_0 of a 7B is ~8GB and near-lossless. Q4_K_M (~4.7GB, faster on CPU) needs the `llama-quantize` binary.

## 2. Create the CT (match the fleet)
`pct create <id> local:vztmpl/ubuntu-24.04-standard...` with a static IP, `--unprivileged 1 --features nesting=1,keyctl=1 --onboot 1`, Europe/London tz, YubiKey key in /root/.ssh/authorized_keys, key-only sshd drop-in. Size disk for the GGUF + Ollama's imported COPY + base (give 40GB for a 8GB model; `pct resize <id> rootfs +NNG`). Ubuntu minimal template LACKS `curl` AND `zstd` - `apt-get install -y curl zstd ca-certificates` before the Ollama installer or it fails.

## 3. Bridge the GGUF
Home-3090 and office-fleet are different LANs bridged by the laptop. HTTP-serve the gguf from the source (`python -m http.server`), download to the laptop, `scp` to the CT. (memagent put is buggy - never use it for big files.)

## 4. Import + expose
`ollama create adam-style -f Modelfile` where Modelfile = `FROM /path/model.gguf` + `SYSTEM "..."` + sampling PARAMETERs. Ollama binds 127.0.0.1 by default - for LAN access add a systemd override `/etc/systemd/system/ollama.service.d/override.conf` with `Environment="OLLAMA_HOST=0.0.0.0:11434"`, daemon-reload + restart. Endpoint: POST /v1/chat/completions {model, messages}.

## 5. SPEED: pin to P-cores on hybrid Intel
This is the big CPU-inference win. On a hybrid chip (e.g. i5-1235U = 2 P-cores logical 0-3 @4.4GHz + 8 E-cores 4-11 @3.3GHz), `pct set --cores N` is only a CPU QUOTA, not core-pinning, so Ollama floats its threads onto the slow E-cores. Find P-cores: `cat /sys/devices/cpu_core/cpus`. Pin the CT: add `lxc.cgroup2.cpuset.cpus: 0-3` to /etc/pve/lxc/<id>.conf and `pct reboot <id>` (NOTE: it is `pct reboot`, there is no `pct restart`); verify `pct exec <id> -- cat /sys/fs/cgroup/cpuset.cpus.effective`. Then set Ollama `PARAMETER num_thread` to the pinned thread count and `PARAMETER num_ctx 2048` (don't leave the model's huge native context). Measured: num_ctx+num_thread fix alone took a warm 7B-Q8 restyle from ~100s to ~17s; leaving threads on E-cores is the remaining drag. Sweep num_thread (physical-core count vs with-HT) and read `journalctl -u ollama | grep 'eval rate'`.

## 6. Finish
Every managed box gets ~/INVENTORY.md (teardown manifest). Remove the now-unused base model (`ollama rm qwen2.5:7b`) and build intermediates (merged dir, f16/gguf, llama.cpp clone). Ollama's systemd service auto-starts the model across reboots.
