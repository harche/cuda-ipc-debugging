# DRA Shared GPU CUDA IPC Example

This directory contains a CUDA IPC example using Kubernetes Dynamic Resource Allocation (DRA) to share 2 GPUs between producer and consumer pods.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deploying the Example](#deploying-the-example)
- [Security Analysis Summary](#security-analysis-summary)
- [DRA Configuration](#dra-configuration)
- [GPU Device Selection: CUDA_VISIBLE_DEVICES Approach](#gpu-device-selection-cuda_visible_devices-approach)
- [Monitoring](#monitoring)
- [Cleanup](#cleanup)

## Prerequisites

Ensure your Kubernetes cluster has:
- **NVIDIA GPU DRA Driver** installed and configured
- Nodes with at least 2 NVIDIA GPUs available
- Kubernetes 1.31+ with DRA (Dynamic Resource Allocation) feature enabled


## Deploying the Example

Deploy the resources in sequence:

```bash
# 1. Create namespace and shared GPU resource claim
kubectl apply -f resource-claim.yaml

# 2. Start the producer first (creates shared memory and CUDA IPC handle)
kubectl apply -f producer-pod.yaml

# 3. Wait for producer to be running and ready
kubectl wait --for=condition=Ready pod/cuda-ipc-producer-dra -n cuda-ipc-dra --timeout=60s

# 4. Start the consumer (opens shared memory and processes data)
kubectl apply -f consumer-pod.yaml
```

**Important**: The producer must be running before starting the consumer, as the consumer needs to access the shared memory created by the producer.

## Security Analysis Summary

| Configuration | HostIPC | HostPID | Privileged | Status | Error |
|---------------|---------|---------|------------|--------|-------|
| Baseline      | ✅      | ✅      | ✅         | ✅ SUCCESS | None |
| HostIPC Only Disabled | ❌ | ✅ | ✅ | ✅ SUCCESS | None |
| HostPID Only Disabled | ✅ | ❌ | ✅ | ❌ FAILED | invalid device context |
| Privileged Only Disabled | ✅ | ✅ | ❌ | ✅ SUCCESS | None |
| HostIPC + HostPID Disabled | ❌ | ❌ | ✅ | ❌ FAILED | invalid device context |
| HostIPC + Privileged Disabled | ❌ | ✅ | ❌ | ✅ SUCCESS | None |
| HostPID + Privileged Disabled | ✅ | ❌ | ❌ | ❌ FAILED | invalid device context |
| All Disabled | ❌ | ❌ | ❌ | ❌ FAILED | invalid device context |

### Key Findings

1. **HostIPC is NOT required** for CUDA IPC when using shared volume approach for handle transfer
2. **HostPID is REQUIRED** for CUDA IPC operations - enables GPU context sharing between processes
3. **Privileged mode is NOT required** with DRA - Dynamic Resource Allocation provides better GPU resource management
4. **Minimum security requirements**: `hostPID: true` only (privileged can be disabled)
5. **Recommended configuration**: `hostPID: true` + `privileged: false` for better security
6. **GPU Selection Strategy**: Uses `CUDA_VISIBLE_DEVICES` environment variables for cleaner, more maintainable device selection


### GPU Visibility
- Both pods can see and access both GPUs
- Enhanced GPU enumeration in the code to show all available devices
- CUDA IPC operations work across the shared GPU resources

## DRA Configuration

### ResourceClaim Definition
```yaml
apiVersion: resource.k8s.io/v1beta1
kind: ResourceClaim
metadata:
  namespace: cuda-ipc-dra
  name: shared-dual-gpus
spec:
  devices:
    requests:
    - name: gpu-1
      deviceClassName: gpu.nvidia.com
    - name: gpu-2
      deviceClassName: gpu.nvidia.com
```

### Pod Resource Claims
```yaml
resources:
  claims:
  - name: shared-gpus

resourceClaims:
- name: shared-gpus
  resourceClaimName: shared-dual-gpus
```

## GPU Device Selection: CUDA_VISIBLE_DEVICES Approach

This example uses an  **GPU selection strategy** via environment variables instead of hardcoded device selection in CUDA code.

### Configuration

**Producer Pod:**
```yaml
env:
- name: CUDA_VISIBLE_DEVICES
  value: "0"
```

**Consumer Pod:**
```yaml
env:
- name: CUDA_VISIBLE_DEVICES
  value: "1"
```

### How It Works

1. **Producer Container** (`CUDA_VISIBLE_DEVICES=0`):
   - CUDA runtime filters to show only physical GPU 0
   - Application sees: `Found 1 GPU(s)` (physical GPU 0 appears as device 0)
   - Creates IPC handle on physical GPU 0

2. **Consumer Container** (`CUDA_VISIBLE_DEVICES=1`):
   - CUDA runtime filters to show only physical GPU 1
   - Application sees: `Found 1 GPU(s)` (physical GPU 1 appears as device 0)
   - Opens IPC handle from physical GPU 0 (cross-GPU access via DRA)

### Technical Implementation

```cuda
// Both producer and consumer use identical device selection:
err = cudaSetDevice(0);  // Always use device 0 (the only visible device)
```

## Monitoring

Check resource claim status:
```bash
kubectl get resourceclaim -n cuda-ipc-dra
kubectl describe resourceclaim shared-dual-gpus -n cuda-ipc-dra
```

Check pod status and logs:
```bash
kubectl get pods -n cuda-ipc-dra
kubectl logs cuda-ipc-producer-dra -n cuda-ipc-dra
kubectl logs cuda-ipc-consumer-dra -n cuda-ipc-dra
```

Expected output should show both pods detecting multiple GPUs:
```
Producer: Found 2 GPU(s)
Producer: GPU 0: NVIDIA GeForce RTX 4090
Producer: GPU 1: NVIDIA GeForce RTX 4090
```

## Cleanup

```bash
kubectl delete -f consumer-pod.yaml
kubectl delete -f producer-pod.yaml
kubectl delete -f resource-claim.yaml
```