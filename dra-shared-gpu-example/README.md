# DRA Shared GPU CUDA IPC Example

This directory contains a CUDA IPC example using Kubernetes Dynamic Resource Allocation (DRA) to share 2 GPUs between producer and consumer pods.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deploying the Example](#deploying-the-example)
- [Security Analysis Summary](#security-analysis-summary)
- [DRA Configuration](#dra-configuration)
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