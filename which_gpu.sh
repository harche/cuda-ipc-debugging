echo "NVIDIA_VISIBLE_DEVICES=$NVIDIA_VISIBLE_DEVICES"
ALLOCATED_GPU_UUID=$(ls "$NVIDIA_VISIBLE_DEVICES" | head -n 1)
echo "Allocated GPU UUID:  $ALLOCATED_GPU_UUID"
GPU_MAP_DATA=$(nvidia-smi --query-gpu=uuid,index --format=csv,noheader)
echo "nvidia-smi output for UUIDs and indices:"
echo "$GPU_MAP_DATA"

export ALLOCATED_GPU_INDEX=$(
  echo "$GPU_MAP_DATA" |
  awk -F',' -v target_uuid="$ALLOCATED_GPU_UUID" '
    {
      gsub(/^[ \t]+|[ \t]+$/, "", $1)
      if ($1 == target_uuid) {
        gsub(/^[ \t]+|[ \t]+$/, "", $2)
        print $2
        exit
      }
    }'
)
