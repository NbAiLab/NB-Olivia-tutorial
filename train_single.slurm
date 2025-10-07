#!/bin/bash
#SBATCH --account=nn30001k
#SBATCH --partition=accel
#SBATCH --time=04:00:00
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --job-name=nb_train_1gpu
#SBATCH --output=/cluster/work/projects/nn30001k/%u/logs/nb_train_1gpu_%j.out
#SBATCH --error=/cluster/work/projects/nn30001k/%u/logs/nb_train_1gpu_%j.err
#SBATCH --open-mode=append

set -euo pipefail

MYROOT=/cluster/work/projects/nn30001k/$USER
CODEDIR=$MYROOT/code
CONTAINER=$MYROOT/containers/pytorch_nvidia_25.06_arm64.sif
OVERLAY=$MYROOT/overlays/myenv_998211f8576b_arm64.sqsh  # Adjust automatically if hash changes

SCRIPT=$MYROOT/nb-gpt-posttrain/src/nb_gpt_posttrain/nynorsk_translation/train_sft_bokmal_nynorsk.py

export HF_HOME="$MYROOT/hf_cache"
export HF_DATASETS_CACHE="$HF_HOME/datasets"
mkdir -p "$HF_HOME" "$HF_DATASETS_CACHE"

# Hugging Face token (optional)
if [ -f /cluster/home/$USER/.huggingface/token ]; then
  export HUGGING_FACE_HUB_TOKEN="$(tr -d '\n' </cluster/home/$USER/.huggingface/token)"
  export HF_TOKEN="$HUGGING_FACE_HUB_TOKEN"
  export APPTAINERENV_HUGGING_FACE_HUB_TOKEN="$HUGGING_FACE_HUB_TOKEN"
  export APPTAINERENV_HF_TOKEN="$HF_TOKEN"
fi

# === Training ===
apptainer exec --nv \
  -B "$MYROOT":"$MYROOT" \
  -B "$OVERLAY":/user-software:image-src=/ \
  "$CONTAINER" bash -lc "
    set -euo pipefail
    source /user-software/bin/activate
    python '$SCRIPT' \
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
