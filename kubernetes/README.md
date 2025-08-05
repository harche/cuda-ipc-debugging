# Kubernetes Deployment for CUDA IPC Example

This directory contains manifests and a Dockerfile for running the CUDA IPC
example on vanilla Kubernetes using separate producer and consumer pods.

## Using Pre-built Image

The manifests use the pre-built image `quay.io/harpatil/cuda-ipc:latest` which is ready to use.

## Building Custom Image (Optional)

Only build a custom image if you need to modify the CUDA IPC example code:

```bash
docker build -t your-registry/cuda-ipc:latest -f Dockerfile ..
docker push your-registry/cuda-ipc:latest
```

Then update the image references in `pods.yaml` to point to your custom image.

## Prerequisites

Ensure your Kubernetes cluster has:
- NVIDIA GPU support (NVIDIA device plugin installed)
- Nodes with NVIDIA GPUs available
- Container runtime that supports GPU access (containerd/docker with nvidia-container-runtime)

## Deploying Producer and Consumer Pods

Deploy the producer and consumer pods in sequence to ensure proper CUDA IPC setup:

```bash
# 1. Start the producer first (creates shared memory and CUDA IPC handle)
kubectl apply -f producer-pod.yaml

# 2. Wait for producer to be running and ready
kubectl wait --for=condition=Ready pod/producer --timeout=60s

# 3. Start the consumer (opens shared memory and processes data)
kubectl apply -f consumer-pod.yaml
```

**Important**: The producer must be running before starting the consumer, as the consumer needs to access the shared memory created by the producer.

## Key Configuration

- `hostIPC: true` is required to share CUDA IPC handles between pods
- `IPC_LOCK` capability is needed for CUDA IPC operations
- Both pods must run on the same GPU node (enforced via nodeSelector)
- Each pod requests 1 GPU resource
- Producer creates shared memory, consumer accesses it

## Monitoring

Check pod status and logs:

```bash
kubectl get pods
kubectl logs producer
kubectl logs consumer
```

## GPU Debugging and Monitoring

### Running nvidia-smi Commands

A debugging pod is provided to run nvidia-smi commands and inspect GPU topology:

```bash
# Deploy the GPU driver pod (runs indefinitely)
kubectl apply -f gpu-driver-pod.yaml

# Wait for the pod to be ready
kubectl wait --for=condition=ready pod/gpu-driver-pod --timeout=60s

# Execute nvidia-smi commands interactively
kubectl exec -it gpu-driver-pod -- nvidia-smi
kubectl exec -it gpu-driver-pod -- nvidia-smi topo -m
kubectl exec -it gpu-driver-pod -- nvidia-smi topo -p2p r
kubectl exec -it gpu-driver-pod -- nvidia-smi topo -p2p n

# Or get a shell for extended debugging
kubectl exec -it gpu-driver-pod -- /bin/bash
```

The gpu-driver-pod has:
- Privileged access to see all GPUs on the node
- Host networking and PID namespace access
- Direct access to /dev and NVIDIA driver paths
- Runs indefinitely for interactive debugging

## Cleanup

```bash
kubectl delete pod producer consumer gpu-driver-pod
# or
kubectl delete -f producer-pod.yaml -f consumer-pod.yaml -f gpu-driver-pod.yaml
```
