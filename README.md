# 🧠 Olivia Training Environment – National Library of Norway (Project nn30001k)

This document explains how to set up and run **language model training on Olivia**, Norway’s national supercomputer.  

The guide is reproducible for users at the National Library under project `nn30001k` and is built around **Apptainer containers** and **SquashFS overlays** for reproducible environments.  

It might be useful for others as well, so this repository is public. Thanks to Magnar Bjørve at NRIS for assisting with this setup.

---

## 📦 Files to download

From this repository:

```bash
wget https://raw.githubusercontent.com/NbAiLab/NB-Olivia-tutorial/main/build_overlay.slurm
wget https://raw.githubusercontent.com/NbAiLab/NB-Olivia-tutorial/main/train_single.slurm
wget https://raw.githubusercontent.com/NbAiLab/NB-Olivia-tutorial/main/requirements_simplified.txt
wget https://raw.githubusercontent.com/NbAiLab/NB-Olivia-tutorial/main/test_imports.py
wget https://raw.githubusercontent.com/NbAiLab/NB-Olivia-tutorial/main/README.md
```

Place all of these files in:

```
/cluster/work/projects/nn30001k/$USER/code/
```

---

## 📚 Overview

Olivia’s compute nodes run Apptainer containers on a shared parallel filesystem (Lustre).  
Because Lustre performs poorly with many small files, we package Python environments into a **compressed read-only overlay** (`.sqsh`).  
This overlay is mounted together with a base container at runtime.

| Component | Description |
|------------|-------------|
| `pytorch_nvidia_25.06_arm64.sif` | Base container with CUDA + PyTorch |
| `myenv_<hash>_arm64.sqsh` | Squashed Python venv overlay |
| `build_overlay.slurm` | Builds the overlay |
| `train_single.slurm` | Runs training |
| `requirements_simplified.txt` | Python requirements |
| `test_imports.py` | Sanity test of the environment |
| `nb-gpt-posttrain` | Example training repository (Nynorsk/Bokmål SFT) |

---

## 🧩 Directory layout

```
/cluster/work/projects/nn30001k/$USER/
├── apptainer_cache/       # Cache for pulled images
├── containers/            # Base .sif containers
├── overlays/              # Squashed Python venvs (.sqsh)
├── code/                  # Scripts, requirements, helper code
├── nb-gpt-posttrain/      # Training repo (large)
├── runs/                  # Output models & checkpoints
├── logs/                  # SLURM logs
└── hf_cache/              # Hugging Face cache
```

---

## ⚙️ 1. Clone the training repository

```bash
cd /cluster/work/projects/nn30001k/$USER/
git clone https://github.com/NationalLibraryOfNorway/nb-gpt-posttrain.git
```

---

## ⚙️ 2. Create base directories

```bash
cd /cluster/work/projects/nn30001k/$USER/
mkdir -p {apptainer_cache,containers,overlays,code,runs,logs,hf_cache}
```

---

## ⚙️ 3. Pull the base container

```bash
export MYROOT=/cluster/work/projects/nn30001k/$USER
export APPTAINER_CACHEDIR=$MYROOT/apptainer_cache

apptainer pull --arch arm64 \
  $MYROOT/containers/pytorch_nvidia_25.06_arm64.sif \
  docker://nvcr.io/nvidia/pytorch:25.06-py3
```

---

## ⚙️ 4. Create a minimal requirements file

`requirements_simplified.txt` (already included):

```
trl
datasets
sacrebleu
wandb
```

---

## ⚙️ 5. Build the overlay

Submit the job:

```bash
cd /cluster/work/projects/nn30001k/$USER/code
sbatch build_overlay.slurm
```

Result:

```
/cluster/work/projects/nn30001k/$USER/overlays/myenv_<hash>_arm64.sqsh
```

### Overlay naming

```
myenv_<12-char SHA256 hash of requirements_simplified.txt>_arm64.sqsh
```

Example:
```
myenv_998211f8576b_arm64.sqsh
```

---

## ⚙️ 6. Running a training job

Submit:

```bash
cd /cluster/work/projects/nn30001k/$USER/
sbatch code/train_single.slurm
```

Monitor:

```bash
tail -f logs/nb_train_1gpu_*.{out,err}
```

---

## 🧠 7. Overlay system explained

The `.sqsh` file is a **read-only compressed filesystem** containing a Python virtual environment.

Mount order:

```
Base container (.sif)
  ↓
Overlay (.sqsh)
  ↓
Merged environment
```

Inside the container:

```
/user-software/bin/activate
/user-software/lib/python3.x/site-packages/
```

---

## 🔁 8. Updating packages

To add packages:

1. Edit `requirements_simplified.txt`
2. Run:
   ```bash
   cd /cluster/work/projects/nn30001k/$USER/code
   sbatch build_overlay.slurm
   ```
3. A new `.sqsh` with a new hash will be created.

---

## 🌐 9. Proxy configuration

Proxy settings (already inside the SLURM scripts):

```bash
export http_proxy=http://10.63.2.48:3128/
export https_proxy=http://10.63.2.48:3128/
export no_proxy="localhost,127.0.0.1,.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
```

---

## 🔑 10. Hugging Face authentication

```bash
mkdir -p ~/.huggingface
echo "<your_token_here>" > ~/.huggingface/token
```

The scripts automatically export `HF_TOKEN` inside the container.

---

## 💾 11. Logs and outputs

| Path | Contents |
|------|-----------|
| `logs/` | SLURM logs |
| `runs/` | Training outputs |
| `hf_cache/` | Hugging Face cache |

---

## 🧭 12. Typical workflow

```bash
cd /cluster/work/projects/nn30001k/$USER/
git clone https://github.com/NationalLibraryOfNorway/nb-gpt-posttrain.git
mkdir -p {apptainer_cache,containers,overlays,code,runs,logs,hf_cache}
apptainer pull --arch arm64 containers/pytorch_nvidia_25.06_arm64.sif docker://nvcr.io/nvidia/pytorch:25.06-py3
wget -P code/ https://raw.githubusercontent.com/NbAiLab/NB-Olivia-tutorial/main/build_overlay.slurm
wget -P code/ https://raw.githubusercontent.com/NbAiLab/NB-Olivia-tutorial/main/train_single.slurm
wget -P code/ https://raw.githubusercontent.com/NbAiLab/NB-Olivia-tutorial/main/requirements_simplified.txt
wget -P code/ https://raw.githubusercontent.com/NbAiLab/NB-Olivia-tutorial/main/test_imports.py
sbatch code/build_overlay.slurm
sbatch code/train_single.slurm
```

---

## 🧑‍💻 Maintainer

**Per Egil Kummervold**  
Senior Researcher – National Library of Norway  
Project: `nn30001k`
