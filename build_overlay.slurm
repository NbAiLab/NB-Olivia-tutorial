#!/bin/bash
#SBATCH --account=nn30001k
#SBATCH --partition=accel
#SBATCH --time=00:30:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gpus=1
#SBATCH --job-name=build_overlay
#SBATCH --chdir=/cluster/work/projects/nn30001k/$USER/code
#SBATCH --output=/cluster/work/projects/nn30001k/%u/logs/build_overlay_%j.out
#SBATCH --error=/cluster/work/projects/nn30001k/%u/logs/build_overlay_%j.err
#SBATCH --open-mode=append

set -euo pipefail
set -x

# --- Paths ---
export MYROOT="/cluster/work/projects/nn30001k/$USER"
export CODEDIR="$MYROOT/code"
export OVERLAYDIR="$MYROOT/overlays"
export CONTAINER="$MYROOT/containers/pytorch_nvidia_25.06_arm64.sif"
mkdir -p "$OVERLAYDIR" "$MYROOT/logs"

# --- Proxy (host + inside container) ---
export http_proxy="http://10.63.2.48:3128/"
export https_proxy="http://10.63.2.48:3128/"
export no_proxy="localhost,127.0.0.1,.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
export APPTAINERENV_http_proxy="$http_proxy"
export APPTAINERENV_https_proxy="$https_proxy"
export APPTAINERENV_no_proxy="$no_proxy"

# --- HF caches on project space ---
export HF_HOME="$MYROOT/hf_cache"
export HF_DATASETS_CACHE="$MYROOT/hf_cache/datasets"

# --- HF auth (optional) ---
if [ -f /cluster/home/$USER/.huggingface/token ]; then
  export HUGGING_FACE_HUB_TOKEN="$(tr -d '\n' </cluster/home/$USER/.huggingface/token)"
  export HF_TOKEN="$HUGGING_FACE_HUB_TOKEN"
fi

# --- PyTorch allocator (compatible) ---
export PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:128"

# --- Overlay name (deterministic hash + arch suffix) ---
REQ_HASH=$(sha256sum "$CODEDIR/requirements_simplified.txt" | awk '{print $1}' | cut -c1-12)
ENV_NAME="myenv_${REQ_HASH}_arm64"
OUT_SQSH="$OVERLAYDIR/${ENV_NAME}.sqsh"

echo "Overlay: $ENV_NAME"
echo "Target : $OUT_SQSH"
ls -lh "$CONTAINER"

# --- Create venv inside the container using system site-packages ---
apptainer exec --nv --bind "$CODEDIR" "$CONTAINER" bash -lc "
  python -m venv myenv --system-site-packages &&
  source myenv/bin/activate &&
  pip install -U pip &&
  pip install -r requirements_simplified.txt &&
  python test_imports.py
"

# --- Squash venv to a single file (xz for wide compatibility, drop xattrs) ---
rm -f "$OUT_SQSH"
mksquashfs myenv "$OUT_SQSH" -noappend -comp xz -b 1M -no-xattrs
rm -rf myenv
ls -lh "$OUT_SQSH"

# --- Test overlay runtime ---
export APPTAINERENV_PREPEND_PATH=/user-software/bin
apptainer exec --nv \
  -B "$CODEDIR" \
  -B "$OUT_SQSH":/user-software:image-src=/ \
  "$CONTAINER" \
  bash -lc "source /user-software/bin/activate && python $CODEDIR/test_imports.py"

echo "OK: overlay ready at $OUT_SQSH"
