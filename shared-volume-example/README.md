# Shared Volume CUDA IPC Example

This directory contains a simple CUDA IPC example using shared volumes to transfer IPC handles between producer and consumer pods on Kubernetes.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deploying the Example](#deploying-the-example)
- [Security Analysis Summary](#security-analysis-summary)
- [Detailed Test Results](#detailed-test-results)
  - [Pod Status with HostIPC, HostPID, and Privileged Enabled](#pod-status-with-hostipc-hostpid-and-privileged-enabled)
  - [Pod Status with HostIPC Disabled Only](#pod-status-with-hostipc-disabled-only)
  - [Pod Status with HostPID Disabled Only](#pod-status-with-hostpid-disabled-only)
  - [Pod Status with Privileged Disabled Only](#pod-status-with-privileged-disabled-only)
  - [Pod Status with HostIPC and HostPID Disabled](#pod-status-with-hostipc-and-hostpid-disabled)
  - [Pod Status with HostIPC and Privileged Disabled](#pod-status-with-hostipc-and-privileged-disabled)
  - [Pod Status with HostPID and Privileged Disabled](#pod-status-with-hostpid-and-privileged-disabled)
  - [Pod Status with All Security Features Disabled](#pod-status-with-all-security-features-disabled)
- [Key Configuration](#key-configuration)
- [Architecture Differences](#architecture-differences)
- [Monitoring](#monitoring)
- [Cleanup](#cleanup)

## Prerequisites

Ensure your Kubernetes cluster has:
- NVIDIA GPU support (NVIDIA device plugin installed)
- Nodes with NVIDIA GPUs available
- Container runtime that supports GPU access (containerd/docker with nvidia-container-runtime)

## Deploying the Example

Deploy the producer and consumer pods in sequence:

```bash
# 1. Start the producer first (creates shared memory and CUDA IPC handle)
kubectl apply -f producer-pod.yaml

# 2. Wait for producer to be running and ready
kubectl wait --for=condition=Ready pod/cuda-ipc-producer-simple --timeout=60s

# 3. Start the consumer (opens shared memory and processes data)
kubectl apply -f consumer-pod.yaml
```

**Important**: The producer must be running before starting the consumer, as the consumer needs to access the shared memory created by the producer.

## Security Analysis Summary

| Configuration | HostIPC | HostPID | Privileged | Status | Error |
|---------------|---------|---------|------------|--------|-------|
| Baseline      | ✅      | ✅      | ✅         | ✅ SUCCESS | None |
| HostIPC Only Disabled | ❌ | ✅ | ✅ | ✅ SUCCESS | None |
| HostPID Only Disabled | ✅ | ❌ | ✅ | ❌ FAILED | invalid device context |
| Privileged Only Disabled | ✅ | ✅ | ❌ | ❌ FAILED | invalid argument |
| HostIPC + HostPID Disabled | ❌ | ❌ | ✅ | ❌ FAILED | invalid device context |
| HostIPC + Privileged Disabled | ❌ | ✅ | ❌ | ❌ FAILED | invalid argument |
| HostPID + Privileged Disabled | ✅ | ❌ | ❌ | ❌ FAILED | invalid device context |
| All Disabled | ❌ | ❌ | ❌ | ❌ FAILED | invalid device context |

### Key Findings

1. **HostIPC is NOT required** for CUDA IPC when using shared volume approach for handle transfer
2. **HostPID is REQUIRED** for CUDA IPC operations - enables GPU context sharing between processes
3. **Privileged mode is REQUIRED** for CUDA IPC operations - enables low-level GPU memory operations
4. **Minimum security requirements**: `hostPID: true` + `privileged: true`
5. **Recommended configuration**: Keep all three enabled for maximum compatibility

## Detailed Test Results

### Pod Status with HostIPC, HostPID, and Privileged Enabled

**Configuration**: `hostIPC: true`, `hostPID: true`, `privileged: true`

**Status**: ✅ **SUCCESS** (Baseline)

Running pods in the default namespace:

```
NAME                       READY   STATUS    RESTARTS   AGE
cuda-ipc-consumer-simple   1/1     Running   0          5m1s
cuda-ipc-producer-simple   1/1     Running   0          5m53s
```

#### Producer Pod Output
```
Compiling producer...
Starting producer...
Producer: Initializing CUDA...
Producer: Allocating GPU memory...
Producer: Writing test data to GPU memory...
Producer: Creating IPC handle...
Producer: Writing handle to shared volume...
Producer: Success! Memory contains values 42, 43, 44, 45, 46...
Producer: Hanging infinitely to keep GPU memory alive...
```

#### Consumer Pod Output
```
Consumer: Waiting for producer to create handle...
Consumer: Handle file found!
Compiling consumer...
Starting consumer...
Consumer: Initializing CUDA...
Consumer: Reading IPC handle from shared volume...
Consumer: Opening IPC memory handle...
Consumer: Successfully opened shared GPU memory!
Consumer: First 10 values from shared memory: 42 43 44 45 46 47 48 49 50 51
Consumer: ✓ Data verification PASSED!
Consumer: Success! Hanging infinitely...
```

### Pod Status with HostIPC Disabled Only

**Configuration**: `hostIPC: false`, `hostPID: true`, `privileged: true`

**Status**: ✅ **SUCCESS**

Both pods run successfully and CUDA IPC works correctly. Disabling HostIPC does not affect CUDA IPC functionality when using shared volume for handle transfer.

```
NAME                       READY   STATUS    RESTARTS   AGE
cuda-ipc-consumer-simple   1/1     Running   0          14s
cuda-ipc-producer-simple   1/1     Running   0          15s
```

Consumer output shows successful data verification:
```
Consumer: ✓ Data verification PASSED!
Consumer: Success! Hanging infinitely...
```

### Pod Status with HostPID Disabled Only

**Configuration**: `hostIPC: true`, `hostPID: false`, `privileged: true`

**Status**: ❌ **FAILED**

Consumer pod fails with "invalid device context" error when attempting to open the IPC handle.

```
NAME                       READY   STATUS    RESTARTS   AGE
cuda-ipc-consumer-simple   0/1     Error     0          13s
cuda-ipc-producer-simple   1/1     Running   0          14s
```

Consumer error:
```
Consumer: Opening IPC memory handle...
ERROR opening IPC handle: invalid device context
```

**Root Cause**: HostPID is required for CUDA IPC operations. Without access to the host PID namespace, the consumer cannot properly establish a connection to the GPU context created by the producer process.

### Pod Status with Privileged Disabled Only

**Configuration**: `hostIPC: true`, `hostPID: true`, `privileged: false`

**Status**: ❌ **FAILED**

Consumer pod fails with "invalid argument" error when attempting to open the IPC handle.

```
NAME                       READY   STATUS    RESTARTS   AGE
cuda-ipc-consumer-simple   0/1     Error     0          14s
cuda-ipc-producer-simple   1/1     Running   0          14s
```

Consumer error:
```
Consumer: Opening IPC memory handle...
ERROR opening IPC handle: invalid argument
```

**Root Cause**: Privileged mode is required for CUDA IPC operations. Without privileged access, the container cannot perform the low-level GPU memory operations needed for IPC handle opening.

### Pod Status with HostIPC and HostPID Disabled

**Configuration**: `hostIPC: false`, `hostPID: false`, `privileged: true`

**Status**: ❌ **FAILED**

Consumer pod fails with "invalid device context" error when attempting to open the IPC handle.

```
NAME                       READY   STATUS    RESTARTS   AGE
cuda-ipc-consumer-simple   0/1     Error     0          13s
cuda-ipc-producer-simple   1/1     Running   0          15s
```

Consumer error:
```
Consumer: Opening IPC memory handle...
ERROR opening IPC handle: invalid device context
```

**Root Cause**: HostPID is required for CUDA IPC operations. Even with HostIPC disabled working individually, the lack of HostPID prevents proper GPU context sharing.

### Pod Status with HostIPC and Privileged Disabled

**Configuration**: `hostIPC: false`, `hostPID: true`, `privileged: false`

**Status**: ❌ **FAILED**

Consumer pod fails with "invalid argument" error when attempting to open the IPC handle.

```
NAME                       READY   STATUS    RESTARTS   AGE
cuda-ipc-consumer-simple   0/1     Error     0          14s
cuda-ipc-producer-simple   1/1     Running   0          14s
```

Consumer error:
```
Consumer: Opening IPC memory handle...
ERROR opening IPC handle: invalid argument
```

**Root Cause**: Privileged mode is required for CUDA IPC operations regardless of IPC namespace settings.

### Pod Status with HostPID and Privileged Disabled

**Configuration**: `hostIPC: true`, `hostPID: false`, `privileged: false`

**Status**: ❌ **FAILED**

Consumer pod fails with "invalid device context" error when attempting to open the IPC handle.

```
NAME                       READY   STATUS    RESTARTS   AGE
cuda-ipc-consumer-simple   0/1     Error     0          10s
cuda-ipc-producer-simple   1/1     Running   0          11s
```

Consumer error:
```
Consumer: Opening IPC memory handle...
ERROR opening IPC handle: invalid device context
```

**Root Cause**: Both HostPID and Privileged mode are required. HostPID provides process visibility for GPU context sharing, while Privileged mode enables low-level GPU operations.

### Pod Status with All Security Features Disabled

**Configuration**: `hostIPC: false`, `hostPID: false`, `privileged: false`

**Status**: ❌ **FAILED**

Consumer pod fails with "invalid device context" error when attempting to open the IPC handle.

```
NAME                       READY   STATUS    RESTARTS   AGE
cuda-ipc-consumer-simple   0/1     Error     0          10s
cuda-ipc-producer-simple   1/1     Running   0          11s
```

Consumer error:
```
Consumer: Opening IPC memory handle...
ERROR opening IPC handle: invalid device context
```

**Root Cause**: Multiple security restrictions prevent CUDA IPC operations. Both HostPID and Privileged mode are essential for CUDA IPC functionality.

## Key Configuration

Both pods share the following configuration:
- `hostIPC: true` - Required to share CUDA IPC handles between pods
- `hostPID: true` - Enables process visibility between pods
- `IPC_LOCK` capability - Needed for CUDA IPC operations
- `privileged: true` - Required for GPU access and IPC operations
- `nodeSelector` - Ensures both pods run on GPU-enabled nodes
- `nvidia.com/gpu: 1` - Each pod requests 1 GPU resource
- Shared volume at `/tmp/cuda-ipc-shared` on the host, mounted to `/shared` in containers

## Architecture Differences

This example differs from the direct IPC approach by using a shared volume to transfer IPC handles:

- **Shared Volume**: IPC handles are written to a file on a shared volume
- **File-based Communication**: Producer writes handle to `/shared/cuda_ipc_handle.dat`, consumer reads it
- **Simpler Setup**: No need for complex process coordination or shared memory segments
- **Host Path Volume**: Uses `/tmp/cuda-ipc-shared` on the host for persistence

## Monitoring

Check pod status and logs:

```bash
kubectl get pods
kubectl logs cuda-ipc-producer-simple
kubectl logs cuda-ipc-consumer-simple
```

## Cleanup

```bash
kubectl delete pod cuda-ipc-producer-simple cuda-ipc-consumer-simple
# or
kubectl delete -f producer-pod.yaml -f consumer-pod.yaml
```