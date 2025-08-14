# DRA Shared GPU CUDA IPC Example

This directory contains a CUDA IPC example using Kubernetes Dynamic Resource Allocation (DRA) to share 2 GPUs between producer and consumer pods.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Architecture Overview](#architecture-overview)
- [Deploying the Example](#deploying-the-example)
- [Key Features](#key-features)
- [DRA Configuration](#dra-configuration)
- [Monitoring](#monitoring)
- [Cleanup](#cleanup)
- [Differences from Shared Volume Example](#differences-from-shared-volume-example)

## Prerequisites

Ensure your Kubernetes cluster has:
- **NVIDIA GPU DRA Driver** installed and configured
- Nodes with at least 2 NVIDIA GPUs available
- Container runtime that supports GPU access (containerd/docker with nvidia-container-runtime)
- Kubernetes 1.31+ with DRA (Dynamic Resource Allocation) feature enabled

## Architecture Overview

This example demonstrates CUDA IPC using Dynamic Resource Allocation (DRA) where:
- A **ResourceClaim** requests 2 GPUs that can be shared between pods
- Both **producer** and **consumer** pods reference the same ResourceClaim
- Both pods can access all 2 GPUs simultaneously
- CUDA IPC handles are transferred via shared volume between pods

### DRA Benefits
- **Resource Sharing**: Multiple pods can share the same GPU resources
- **Fine-grained Control**: Request specific GPU configurations
- **Kubernetes Native**: Uses standard Kubernetes resource management
- **Dynamic Allocation**: Resources allocated at pod scheduling time

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

## Key Features

### Resource Claim Configuration
- **Namespace**: `cuda-ipc-dra`
- **ResourceClaim**: `shared-dual-gpus` requesting 2 GPUs
- **Device Class**: `gpu.nvidia.com`
- **Sharing**: Both pods reference the same ResourceClaim

### Pod Configuration
Both pods share the following configuration:
- `hostIPC: true` - Required for CUDA IPC operations
- `hostPID: true` - Enables process visibility between pods
- `privileged: true` - Required for GPU access and IPC operations
- `IPC_LOCK` capability - Needed for CUDA IPC operations
- **DRA Resource Claims** - Both pods claim access to `shared-dual-gpus`
- Shared volume at `/tmp/cuda-ipc-shared-dra` on host, mounted to `/shared` in containers

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

## Differences from Shared Volume Example

### Key Differences
1. **Resource Management**: Uses DRA instead of traditional `nvidia.com/gpu: 1` limits
2. **GPU Sharing**: Both pods can access all GPUs through shared ResourceClaim
3. **Enhanced Visibility**: Code includes GPU enumeration to show all available devices
4. **Namespace Isolation**: Resources are contained within `cuda-ipc-dra` namespace
5. **Future-Ready**: Uses Kubernetes native resource allocation mechanisms

### Similarities
- Same CUDA IPC implementation and handle transfer mechanism
- Same security requirements (`hostPID`, `privileged`, `IPC_LOCK`)
- Same shared volume approach for IPC handle transfer
- Same verification and testing patterns

### Advantages of DRA Approach
- **Better Resource Utilization**: Multiple pods can share the same physical GPUs
- **Flexibility**: Can request specific GPU configurations and quantities
- **Kubernetes Native**: Integrated with Kubernetes resource management
- **Scalability**: Better support for complex GPU sharing scenarios
- **Future Compatibility**: Aligns with Kubernetes evolution for device management

This example demonstrates how CUDA IPC can work in modern Kubernetes environments using Dynamic Resource Allocation for more flexible and efficient GPU resource sharing.