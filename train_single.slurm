#!/bin/bash
#SBATCH --account=nn30001k
#SBATCH --partition=accel
#SBATCH --time=04:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --gpus=1
#SBATCH --job-name=nb_train_1gpu
#SBATCH --chdir=/cluster/work/projects/nn30001k/$USER
#SBATCH --output=/cluster/work/projects/nn30001k/%u/logs/nb_train_1gpu_%j.out
#SBATCH --error=/cluster/work/projects/nn30001k/%u/logs/nb_train_1gpu_%j.err
#SBATCH --open-mode=append

set -euo pipefail
set -x

# --- Paths ---
export MYROOT="/cluster/work/projects/nn30001k/$USER"
export CODEDIR="$MYROOT/code"
export LOGDIR="$MYROOT/logs"
export RUNDIR="$MYROOT/runs"
export CONTAINER="$MYROOT/containers/pytorch_nvidia_25.06_arm64.sif"
mkdir -p "$RUNDIR" "$LOGDIR"

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

# --- PyTorch allocator + dtype ---
export PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:128"
export TORCH_DTYPE="bfloat16"

# --- Resolve overlay from current requirements (arm64 naming) ---
REQ_HASH=$(sha256sum "$CODEDIR/requirements_simplified.txt" | awk '{print $1}' | cut -c1-12)
SQSH="$MYROOT/overlays/myenv_${REQ_HASH}_arm64.sqsh"

# --- Sanity checks ---
[ -s "$CONTAINER" ] || { echo "Missing container: $CONTAINER"; exit 2; }
[ -s "$SQSH" ]      || { echo "Missing overlay: $SQSH (run: sbatch $CODEDIR/build_overlay.slurm)"; exit 3; }

# --- Training script path (repo must be cloned in project space) ---
SCRIPT="$MYROOT/nb-gpt-posttrain/src/nb_gpt_posttrain/nynorsk_translation/train_sft_bokmal_nynorsk.py"
[ -f "$SCRIPT" ] || { echo "Missing script: $SCRIPT (did you git clone the repo?)"; exit 4; }

TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="$RUNDIR/${TS}_qwen06b_sft"
mkdir -p "$OUTDIR"

echo "Using container: $CONTAINER"
echo "Using overlay  : $SQSH"
echo "Run directory  : $OUTDIR"

# Make the overlay venv binaries visible
export APPTAINERENV_PREPEND_PATH=/user-software/bin

# --- Execute training inside container + overlay ---
apptainer exec --nv \
  -B "$MYROOT":"$MYROOT" \
  -B "$SQSH":/user-software:image-src=/ \
  "$CONTAINER" \
  bash -lc "
    set -euo pipefail
    source /user-software/bin/activate
    python $SCRIPT \
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
  "

echo "Done. Artifacts in: $OUTDIR"
