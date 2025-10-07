# 🧠 Olivia Training Environment – National Library of Norway (Project nn30001k)

This document explains how to set up and run **language model training on Olivia**, Norway’s national supercomputer.  
The guide is reproducible for users at the National Library under project `nn30001k` project and is built around **Apptainer containers** and **SquashFS overlays** for reproducible environments. It might be useful for others as well, so I am putting it public.

---

## 📚 Overview

Olivia’s compute nodes run Apptainer containers on a shared parallel filesystem (Lustre).  
Because Lustre performs poorly with many small files, we package Python environments into a **compressed read-only overlay** (`.sqsh`).  
This overlay is mounted together with a base container at runtime.

The setup consists of:

| Component | Description |
|------------|-------------|
| `pytorch_nvidia_25.06_arm64.sif` | Base container with CUDA + PyTorch |
| `myenv_<hash>_arm64.sqsh` | Squashed virtual environment overlay |
| `build_overlay.slurm` | Builds the overlay from requirements |
| `train_single.slurm` | Runs a training job |
| `requirements_simplified.txt` | List of Python packages to install |
| `nb-gpt-posttrain` | Training repository (Nynorsk/Bokmål SFT example) |

---

## 🧩 Directory layout

Each user should work within their own directory under the shared project space:

```
/cluster/work/projects/nn30001k/<username>/
├── apptainer_cache/       # Cache for pulled images
├── containers/            # Base .sif containers
├── overlays/              # Squashed Python venvs (.sqsh)
├── code/                  # SLURM scripts, requirements, helper code
├── nb-gpt-posttrain/      # Cloned training repo (large)
├── runs/                  # Output models & checkpoints
├── logs/                  # SLURM logs
└── hf_cache/              # Hugging Face cache for datasets/models
```

---

## ⚙️ 1. Clone the training repository
This one is a private repo. Use any training code here, just update the script below.

Do **not** clone into your home directory (it has only ~20 GB).  
Instead, clone inside your project area:

```bash
cd /cluster/work/projects/nn30001k/<username>/
git clone https://github.com/NationalLibraryOfNorway/nb-gpt-posttrain.git
```

---

## ⚙️ 2. Create base directories

```bash
cd /cluster/work/projects/nn30001k/<username>/
mkdir -p {apptainer_cache,containers,overlays,code,runs,logs,hf_cache}
```

---

## ⚙️ 3. Pull the base container

Run this on a **login node** (not compute node):

```bash
export MYROOT=/cluster/work/projects/nn30001k/<username>
export APPTAINER_CACHEDIR=$MYROOT/apptainer_cache

apptainer pull --arch arm64 \
  $MYROOT/containers/pytorch_nvidia_25.06_arm64.sif \
  docker://nvcr.io/nvidia/pytorch:25.06-py3
```

This downloads NVIDIA’s official PyTorch + CUDA container for ARM64 (Olivia’s architecture).

---

## ⚙️ 4. Create the requirements file

Inside your `code/` folder, create a minimal `requirements_simplified.txt`. Add here only the libraries not already contained in the pytorch_nvidia_25.06_arm64.sif:

```
trl
datasets
sacrebleu
wandb
```

Add other packages if needed later (see section **"Updating your overlay"** below).

---

## ⚙️ 5. Build the overlay

The overlay is a **SquashFS filesystem** that contains a Python virtual environment with your required packages.

Submit the build job:

```bash
cd /cluster/work/projects/nn30001k/<username>/code
sbatch build_overlay.slurm
```

When finished, you should see:

```
/cluster/work/projects/nn30001k/<username>/overlays/myenv_<hash>_arm64.sqsh
```

### 🧮 How the overlay is named

The name is deterministic:
```
myenv_<12-char SHA256 hash of requirements_simplified.txt>_arm64.sqsh
```

Example:
```
myenv_998211f8576b_arm64.sqsh
```

This ensures that if two users have the same requirements file, they get the same overlay name.  
If you change the requirements file, a new hash is produced, and therefore a new overlay file is created.

---

## ⚙️ 6. Running a training job

An example training job is included: `train_single.slurm`.

It runs the **Bokmål → Nynorsk SFT** training script from  
[`nb-gpt-posttrain`](https://github.com/NationalLibraryOfNorway/nb-gpt-posttrain).

### Submit job

```bash
cd /cluster/work/projects/nn30001k/<username>/
sbatch code/train_single.slurm
```

### Monitor

```bash
tail -f logs/nb_train_1gpu_*.{out,err}
```

Outputs and checkpoints go to:

```
/cluster/work/projects/nn30001k/<username>/runs/
```

### Training command executed internally

```bash
python /cluster/work/projects/nn30001k/<username>/nb-gpt-posttrain/src/nb_gpt_posttrain/nynorsk_translation/train_sft_bokmal_nynorsk.py \
  --model Qwen/Qwen3-0.6B \
  --wandb_project olivia_test \
  --run_name test1 \
  --train_dataset NbAiLab/merged_npk_ndla_parallel_paragraphs:train \
  --eval_dataset NbAiLab/nynorsk_norm_200eval:validation \
  --train_source_field nb \
  --train_target_field nn \
  --eval_source_field nb \
  --eval_target_field nn_husnorm \
  --per_device_train_batch_size 8 \
  --per_device_eval_batch_size 8 \
  --learning_rate 2e-5 \
  --warmup_steps 10000 \
  --num_train_epochs 6 \
  --eval_steps 5000 \
  --save_steps 50000 \
  --logging_steps 1000
```

Modify `--wandb_project`, `--run_name`, or any hyperparameters in `train_single.slurm` as needed.

---

## 🧠 7. Understanding the overlay system

The overlay (`.sqsh`) is a **compressed read-only filesystem** created with `mksquashfs`.  
It contains a Python virtual environment built on top of the read-only base container.

When the job runs, Apptainer mounts both layers:

```
Base container (pytorch_nvidia_25.06_arm64.sif)
   ↓
Overlay (myenv_<hash>_arm64.sqsh)
   ↓
Merged environment inside container
```

Inside the container, `/user-software` points to your overlay and contains:

```
/user-software/bin/activate
/user-software/lib/python3.x/site-packages/
```

The SLURM scripts run:

```bash
source /user-software/bin/activate
```

so that your custom packages (TRL, Datasets, W&B, etc.) are available immediately.

---

## 🔁 8. Updating or adding packages

If you need more Python packages (e.g. `peft`, `evaluate`, `huggingface_hub`):

1. **Edit** `requirements_simplified.txt`  
   Example:
   ```
   trl
   datasets
   wandb
   peft
   evaluate
   ```
2. **Rebuild the overlay**  
   ```bash
   cd /cluster/work/projects/nn30001k/<username>/code
   sbatch build_overlay.slurm
   ```
3. A new hash will be computed automatically and a new file created, e.g.:
   ```
   myenv_a9b1d35a4b8e_arm64.sqsh
   ```
4. The training script will automatically pick the overlay matching your current `requirements_simplified.txt`.

You can keep several overlays in the `overlays/` directory — each corresponds to a specific requirements configuration.

---

## 🌐 9. Proxy configuration

Olivia requires a network proxy for external access.

The SLURM scripts already export these:

```bash
export http_proxy=http://10.63.2.48:3128/
export https_proxy=http://10.63.2.48:3128/
export no_proxy="localhost,127.0.0.1,.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

export APPTAINERENV_http_proxy=$http_proxy
export APPTAINERENV_https_proxy=$https_proxy
export APPTAINERENV_no_proxy=$no_proxy
```

These variables are also passed **inside** the container so that `pip`, `datasets`, and `wandb` can reach the internet.

---

## 🔑 10. Hugging Face authentication

For gated datasets or models:

```bash
mkdir -p ~/.huggingface
echo "<your_token_here>" > ~/.huggingface/token
```

The scripts automatically read the token and export:

```
HUGGING_FACE_HUB_TOKEN
HF_TOKEN
```

inside the container.

---

## 💾 11. Logs and outputs

| Path | Contents |
|------|-----------|
| `logs/` | SLURM stdout/stderr logs |
| `runs/` | Training outputs and checkpoints |
| `hf_cache/` | Hugging Face cache |

Example:

```bash
tail -f logs/nb_train_1gpu_<JOBID>.out
```

---

## 💰 12. Accounting and billing

- You are billed for **reserved resources**, not for CPU utilization.  
- Example: a 25 min job with 1 GPU + 16 CPUs → about **10 billing hours** (0.43 h × 24 cores ≈ 10).  
- Prices (Oct 2025):  
  - CPU = 0.04 NOK per CPU-hour  
  - GPU = 5.6 NOK per GPU-hour  
- So a short test job costs only a few kroner.

---

## 🧹 13. Cleanup

- Old overlays (`.sqsh`) can be deleted safely once unused.  
- Avoid storing anything in `/cluster/home/<user>`; use project space.  
- Training outputs go in `runs/`.

---

## 🧩 14. Troubleshooting

| Symptom | Cause | Fix |
|----------|--------|-----|
| `Missing overlay` | Overlay not built | `sbatch build_overlay.slurm` |
| `corrupted image: unknown compression algorithm` | Wrong compression | Rebuild overlay (uses `-comp xz`) |
| `dataset not reachable` | Proxy missing | Proxy is set automatically; check job logs |
| `Permission denied` | Expired Kerberos ticket | Run `kinit` |
| `ImportError` | Missing package | Add it to requirements and rebuild |

---

## 🧭 15. Typical workflow summary

```bash
# One-time setup
cd /cluster/work/projects/nn30001k/<user>
git clone https://github.com/NationalLibraryOfNorway/nb-gpt-posttrain.git
mkdir -p {apptainer_cache,containers,overlays,code,runs,logs,hf_cache}
apptainer pull --arch arm64 containers/pytorch_nvidia_25.06_arm64.sif docker://nvcr.io/nvidia/pytorch:25.06-py3

# Update requirements
echo -e "trl\ndatasets\nsacrebleu\nwandb" > code/requirements_simplified.txt

# Build overlay
sbatch code/build_overlay.slurm

# Train
sbatch code/train_single.slurm

# Monitor
tail -f logs/nb_train_1gpu_*.{out,err}
```

---

## 🧑‍💻 Maintainer

**Per Egil Kummervold**  
Senior Researcher – National Library of Norway  
Project `nn30001k`

---

### In short

> **The `.sif` file** is your immutable base container.  
> **The `.sqsh` file** is your personal, versioned Python environment.  
> Together they form a fast, reproducible setup for large-scale training on Olivia.
