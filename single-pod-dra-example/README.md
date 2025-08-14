# Single Pod DRA CUDA IPC Example

This directory contains a CUDA IPC example using a single pod with two containers (producer and consumer) running concurrently on Kubernetes with Dynamic Resource Allocation (DRA).

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deploying the Example](#deploying-the-example)
- [Security Analysis Summary](#security-analysis-summary)
- [GPU Device Selection: CUDA_VISIBLE_DEVICES Approach](#gpu-device-selection-cuda_visible_devices-approach)
- [Monitoring](#monitoring)
- [Cleanup](#cleanup)

## Prerequisites

Ensure your Kubernetes cluster has:
- **NVIDIA GPU DRA Driver** installed and configured
- Nodes with at least 2 NVIDIA GPUs available (for DRA resource sharing)
- Kubernetes 1.31+ with DRA (Dynamic Resource Allocation) feature enabled

## Deploying the Example

Deploy the single pod DRA example:

```bash
# 1. Create namespace and shared GPU resource claim
kubectl apply -f resource-claim.yaml

# 2. Deploy the single pod with both producer and consumer containers
kubectl apply -f single-pod-dra.yaml

# 3. Wait for both containers to be running
kubectl wait --for=condition=Ready pod/cuda-ipc-single-pod-dra -n cuda-ipc-single-dra --timeout=60s
```

**Important**: Both containers run concurrently within the same pod using DRA for enhanced GPU resource sharing. The consumer waits for a ready signal from the producer before starting GPU operations.

## Security Analysis Summary

Based on **confirmed testing results** with the optimal DRA single-pod configuration:

| Configuration | HostIPC | HostPID | shareProcessNamespace | Privileged | Status | Error |
|---------------|---------|---------|----------------------|------------|--------|-------|
| Baseline DRA | ✅ | ✅ | ❌ | ✅ | ✅ SUCCESS | None |
| HostIPC Only Disabled | ❌ | ✅ | ❌ | ✅ | ✅ SUCCESS | None |
| HostPID Only Disabled | ✅ | ❌ | ❌ | ✅ | ❌ FAILED | invalid device context |
| Privileged Only Disabled (DRA Advantage) | ✅ | ✅ | ❌ | ❌ | ✅ SUCCESS | None |
| shareProcessNamespace Alternative | ✅ | ❌ | ✅ | ✅ | ✅ SUCCESS | None |
| shareProcessNamespace + Privileged Disabled | ✅ | ❌ | ✅ | ❌ | ✅ SUCCESS | None |
| HostIPC + HostPID Disabled | ❌ | ❌ | ❌ | ✅ | ❌ FAILED | invalid device context |
| HostIPC + shareProcessNamespace + Privileged Disabled | ❌ | ❌ | ✅ | ❌ | ✅ **CONFIRMED** | None |
| All Security Features Disabled | ❌ | ❌ | ❌ | ❌ | ❌ FAILED | invalid device context |

### Key Findings

1. **HostIPC is NOT required** for CUDA IPC within a single pod using emptyDir volumes (consistent across DRA and traditional approaches)
2. **HostPID OR shareProcessNamespace is REQUIRED** for CUDA IPC operations - enables GPU context sharing between containers
3. **Privileged mode is NOT required with DRA** - Dynamic Resource Allocation provides superior GPU resource management
4. **shareProcessNamespace can replace HostPID** - more secure alternative for process visibility within the pod
5. **Best security configuration**: `shareProcessNamespace: true` + `privileged: false` + `hostIPC: false`
6. **GPU Selection Strategy**: Uses `CUDA_VISIBLE_DEVICES="0,1"` to provide both containers access to all GPUs while maintaining clear device selection

## GPU Device Selection: CUDA_VISIBLE_DEVICES Approach

This example uses an **optimal GPU selection strategy** for single-pod scenarios where both containers need access to multiple GPUs.

### Configuration

**Both Producer and Consumer Containers:**
```yaml
env:
- name: CUDA_VISIBLE_DEVICES
  value: "0,1"
```

### How It Works

1. **Shared GPU Visibility**: Both containers see all available GPUs through `CUDA_VISIBLE_DEVICES="0,1"`
   - Producer sees: `Found 2 GPU(s)` (GPU 0 and GPU 1)
   - Consumer sees: `Found 2 GPU(s)` (GPU 0 and GPU 1)

2. **Device Selection via CUDA Code**:
   - **Producer**: `cudaSetDevice(0)` - Uses GPU 0 for memory allocation and IPC handle creation
   - **Consumer**: `cudaSetDevice(1)` - Uses GPU 1 for IPC handle access and operations

3. **Cross-GPU IPC**: Producer creates IPC handle on GPU 0, Consumer accesses it from GPU 1 via DRA


### Technical Implementation

```cuda
// Producer container:
err = cudaSetDevice(0);  // Use GPU 0 for memory allocation
err = cudaIpcGetMemHandle(&handle, devPtr);  // Create IPC handle on GPU 0

// Consumer container:
err = cudaSetDevice(1);  // Use GPU 1 for operations
err = cudaIpcOpenMemHandle(&devPtr, handle, cudaIpcMemLazyEnablePeerAccess);  // Open handle from GPU 0
```

This approach provides **maximum flexibility** while maintaining **clear device separation** and **optimal security** through DRA's advanced resource management capabilities.

### Container Communication Flow
1. **Producer Container**:
   - Allocates GPU memory using DRA-provided resources
   - Creates CUDA IPC handle
   - Writes handle to shared emptyDir volume
   - Signals readiness to consumer

2. **Consumer Container**:
   - Waits for producer ready signal
   - Reads IPC handle from shared volume
   - Opens shared GPU memory using DRA-managed resources
   - Verifies data integrity


## Monitoring

Check pod and container status:

```bash
# Check overall pod status
kubectl get pods -n cuda-ipc-single-dra

# Check DRA resource claim status
kubectl get resourceclaim -n cuda-ipc-single-dra
kubectl describe resourceclaim single-pod-dual-gpus -n cuda-ipc-single-dra

# Check container logs
kubectl logs cuda-ipc-single-pod-dra -n cuda-ipc-single-dra -c producer
kubectl logs cuda-ipc-single-pod-dra -n cuda-ipc-single-dra -c consumer

# Monitor GPU usage (if available)
kubectl exec cuda-ipc-single-pod-dra -n cuda-ipc-single-dra -c producer -- nvidia-smi
```

Expected output should show both containers detecting multiple GPUs:
```
Producer: Found 2 GPU(s)
Producer: GPU 0: NVIDIA L4
Producer: GPU 1: NVIDIA L4
Consumer: Found 2 GPU(s)
Consumer: GPU 0: NVIDIA L4
Consumer: GPU 1: NVIDIA L4
```

## Cleanup

```bash
kubectl delete -f single-pod-dra.yaml
kubectl delete -f resource-claim.yaml
```