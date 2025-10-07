#!/bin/bash
#SBATCH --account=nn30001k
#SBATCH --partition=accel
#SBATCH --time=00:30:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gpus=1
#SBATCH --job-name=build_overlay
#SBATCH --output=/cluster/work/projects/nn30001k/%u/logs/build_overlay_%j.out
#SBATCH --error=/cluster/work/projects/nn30001k/%u/logs/build_overlay_%j.err
#SBATCH --open-mode=append

set -euo pipefail

# === Paths ===
MYROOT=/cluster/work/projects/nn30001k/$USER
CODEDIR=$MYROOT/code
OVERLAYDIR=$MYROOT/overlays
CONTAINER=$MYROOT/containers/pytorch_nvidia_25.06_arm64.sif
mkdir -p "$OVERLAYDIR" "$MYROOT/logs"

# === Networking & cache ===
export http_proxy="http://10.63.2.48:3128/"
export https_proxy="http://10.63.2.48:3128/"
export no_proxy="localhost,127.0.0.1,.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
export APPTAINERENV_http_proxy="$http_proxy"
export APPTAINERENV_https_proxy="$https_proxy"
export APPTAINERENV_no_proxy="$no_proxy"

export HF_HOME="$MYROOT/hf_cache"
export HF_DATASETS_CACHE="$HF_HOME/datasets"
mkdir -p "$HF_HOME" "$HF_DATASETS_CACHE"

# === Optional Hugging Face token ===
if [ -f /cluster/home/$USER/.huggingface/token ]; then
  export HUGGING_FACE_HUB_TOKEN="$(tr -d '\n' </cluster/home/$USER/.huggingface/token)"
  export HF_TOKEN="$HUGGING_FACE_HUB_TOKEN"
  export APPTAINERENV_HUGGING_FACE_HUB_TOKEN="$HUGGING_FACE_HUB_TOKEN"
  export APPTAINERENV_HF_TOKEN="$HF_TOKEN"
fi

# === Build environment ===
cd "$CODEDIR"
REQ_HASH=$(sha256sum requirements_simplified.txt | awk '{print $1}' | cut -c1-12)
ENV_NAME="myenv_${REQ_HASH}_arm64"
OUT_SQSH="$OVERLAYDIR/${ENV_NAME}.sqsh"
rm -f "$OUT_SQSH"

# Build Python venv using container's torch + CUDA stack
apptainer exec --nv --bind "$CODEDIR" "$CONTAINER" bash -lc "
  set -euo pipefail
  export PYTHONNOUSERSITE=1
  python -m venv myenv --system-site-packages
  source myenv/bin/activate
  python -m pip install -U pip
  python -m pip install -r requirements_simplified.txt
"

# Squash overlay (trailing slash ensures correct mount layout)
mksquashfs myenv/ "$OUT_SQSH" -noappend -comp xz -b 1M -no-xattrs
rm -rf myenv

# Final check (optional but fast)
export APPTAINERENV_PYTHONNOUSERSITE=1
apptainer exec --nv -B "$CODEDIR" -B "$OUT_SQSH":/user-software:image-src=/ "$CONTAINER" \
  bash -lc "source /user-software/bin/activate && python -c 'import sacrebleu, datasets, wandb, trl; print(\"Overlay build OK.\")'"
