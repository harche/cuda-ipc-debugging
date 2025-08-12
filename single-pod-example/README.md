# Single Pod CUDA IPC Example

This directory contains a CUDA IPC example using a single pod with two containers (producer and consumer) running concurrently on Kubernetes.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deploying the Example](#deploying-the-example)
- [Security Analysis Summary](#security-analysis-summary)
- [Why Privileged Mode is Required: Technical Deep Dive](#why-privileged-mode-is-required-technical-deep-dive)
- [Detailed Test Results](#detailed-test-results)
  - [Pod Status with HostIPC, HostPID, and Privileged Enabled](#pod-status-with-hostipc-hostpid-and-privileged-enabled)
  - [Pod Status with HostIPC Disabled Only](#pod-status-with-hostipc-disabled-only)
  - [Pod Status with HostPID Disabled Only](#pod-status-with-hostpid-disabled-only)
  - [Pod Status with Privileged Disabled Only](#pod-status-with-privileged-disabled-only)
  - [Pod Status with HostIPC and HostPID Disabled](#pod-status-with-hostipc-and-hostpid-disabled)
  - [Pod Status with shareProcessNamespace Instead of HostPID](#pod-status-with-shareprocessnamespace-instead-of-hostpid)
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

Deploy the single pod with both producer and consumer containers:

```bash
kubectl apply -f cuda-ipc-pod-concurrent.yaml

# Wait for both containers to be running
kubectl wait --for=condition=Ready pod/cuda-ipc-concurrent-pod --timeout=60s
```

**Important**: Both containers run concurrently within the same pod. The consumer waits for a ready signal from the producer before starting GPU operations.

## Security Analysis Summary

| Configuration | HostIPC | HostPID | shareProcessNamespace | Privileged | Status | Error |
|---------------|---------|---------|----------------------|------------|--------|-------|
| Baseline      | ✅      | ✅      | ❌                   | ✅         | ✅ SUCCESS | None |
| HostIPC Only Disabled | ❌ | ✅ | ❌ | ✅ | ✅ SUCCESS | None |
| HostPID Only Disabled | ✅ | ❌ | ❌ | ✅ | ❌ FAILED | invalid device context |
| Privileged Only Disabled | ✅ | ✅ | ❌ | ❌ | ❌ FAILED | invalid argument |
| HostIPC + HostPID Disabled | ❌ | ❌ | ❌ | ✅ | ❌ FAILED | invalid device context |
| shareProcessNamespace Alternative | ✅ | ❌ | ✅ | ✅ | ✅ SUCCESS | None |
| shareProcessNamespace + Privileged Disabled | ✅ | ❌ | ✅ | ❌ | ❌ FAILED | invalid argument |
| shareProcessNamespace + Privileged Enabled | ✅ | ❌ | ✅ | ✅ | ✅ SUCCESS | None |
| HostIPC Disabled + shareProcessNamespace + Privileged Disabled | ❌ | ❌ | ✅ | ❌ | ❌ FAILED | invalid argument |
| HostIPC Disabled + shareProcessNamespace + Privileged Enabled | ❌ | ❌ | ✅ | ✅ | ✅ SUCCESS | None |

### Key Findings

1. **HostIPC is NOT required** for CUDA IPC within a single pod using emptyDir volumes (confirmed with multiple test scenarios)
2. **HostPID is REQUIRED** for CUDA IPC operations - enables GPU context sharing between containers
3. **shareProcessNamespace can replace HostPID** - alternative approach for process visibility within the pod
4. **Privileged mode is REQUIRED** for CUDA IPC operations - enables access to all GPU devices (confirmed for both hostPID and shareProcessNamespace approaches)
5. **Minimum security requirements**: (`hostPID: true` OR `shareProcessNamespace: true`) + `privileged: true`
6. **Single-pod advantage**: Better isolation than multi-pod approach while maintaining CUDA IPC functionality

## Why Privileged Mode is Required: Technical Deep Dive

The single-pod approach faces the same fundamental GPU device isolation issue as the multi-pod approach. Even within a single pod, **privileged mode is essential** for CUDA IPC operations in Kubernetes:

### The Real Issue: GPU Device Isolation

**Without privileged mode:**
- Kubernetes NVIDIA device plugin still controls GPU device access per container
- Each container within the pod may get restricted access to specific GPU devices
- Result: `cudaIpcOpenMemHandle()` fails with "invalid argument"

**With privileged mode:**
- Both containers can access all GPU devices (`/dev/nvidia0`, `/dev/nvidia1`, etc.)
- Both containers can access the same physical GPU for IPC operations



## Detailed Test Results

### Pod Status with HostIPC, HostPID, and Privileged Enabled

**Configuration**: `hostIPC: true`, `hostPID: true`, `privileged: true`

**Status**: ✅ **SUCCESS** (Baseline)

Both containers run successfully and CUDA IPC works correctly.

```
NAME                      READY   STATUS    RESTARTS   AGE
cuda-ipc-concurrent-pod   2/2     Running   0          19s
```

#### Producer Container Output
```
Producer: Compiling CUDA code...
Producer: Starting execution...
Producer: Initializing CUDA...
Producer: Allocating GPU memory...
Producer: Writing test data to GPU memory...
Producer: Creating IPC handle...
Producer: Writing handle to shared volume...
Producer: Success! Memory contains values 42, 43, 44, 45, 46...
Producer: Ready signal sent. Hanging infinitely to keep memory alive...
```

#### Consumer Container Output
```
Consumer: Waiting for producer to be ready...
Consumer: Producer is ready! Waiting 2 more seconds...
Consumer: Handle file confirmed. Starting processing...
Consumer: Compiling CUDA code...
Consumer: Starting execution...
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

Both containers run successfully and CUDA IPC works correctly. Disabling HostIPC does not affect CUDA IPC functionality when using emptyDir volumes within a single pod.

```
NAME                      READY   STATUS    RESTARTS   AGE
cuda-ipc-concurrent-pod   2/2     Running   0          15s
```

Consumer output shows successful data verification:
```
Consumer: ✓ Data verification PASSED!
Consumer: Success! Hanging infinitely...
```

### Pod Status with HostPID Disabled Only

**Configuration**: `hostIPC: true`, `hostPID: false`, `privileged: true`

**Status**: ❌ **FAILED**

Consumer container fails with "invalid device context" error when attempting to open the IPC handle.

```
NAME                      READY   STATUS   RESTARTS   AGE
cuda-ipc-concurrent-pod   1/2     Error    0          15s
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

Consumer container fails with "invalid argument" error when attempting to open the IPC handle.

```
NAME                      READY   STATUS   RESTARTS   AGE
cuda-ipc-concurrent-pod   1/2     Error    0          15s
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

Consumer container fails with "invalid device context" error when attempting to open the IPC handle.

```
NAME                      READY   STATUS   RESTARTS   AGE
cuda-ipc-concurrent-pod   1/2     Error    0          15s
```

Consumer error:
```
Consumer: Opening IPC memory handle...
ERROR opening IPC handle: invalid device context
```

**Root Cause**: HostPID is required for CUDA IPC operations. Even with privileged mode enabled, the lack of process visibility prevents proper GPU context sharing.

### Pod Status with shareProcessNamespace Instead of HostPID

**Configuration**: `hostIPC: true`, `shareProcessNamespace: true`, `privileged: true`

**Status**: ✅ **SUCCESS**

This is a **significant finding** - `shareProcessNamespace: true` can successfully replace `hostPID: true` for single-pod CUDA IPC operations.

```
NAME                      READY   STATUS    RESTARTS   AGE
cuda-ipc-concurrent-pod   2/2     Running   0          16s
```

Consumer output shows successful data verification:
```
Consumer: ✓ Data verification PASSED!
Consumer: Success! Hanging infinitely...
```

**Technical Explanation**: `shareProcessNamespace: true` enables process visibility between containers within the same pod, providing the necessary process context sharing for CUDA IPC without requiring host-level PID namespace access. This is **more secure** than `hostPID: true` while maintaining functionality.

## Monitoring

Check pod and container status:

```bash
kubectl get pods
kubectl logs cuda-ipc-concurrent-pod -c producer
kubectl logs cuda-ipc-concurrent-pod -c consumer
```

## Cleanup

```bash
kubectl delete pod cuda-ipc-concurrent-pod
# or
kubectl delete -f single-pod-test.yaml
```