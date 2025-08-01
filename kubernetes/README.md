# Kubernetes Deployment for CUDA IPC Example

This directory contains manifests and a Dockerfile for running the CUDA IPC
example on vanilla Kubernetes using separate producer and consumer pods.

## Using Pre-built Image

The manifests use the pre-built image `quay.io/harpatil/cuda-ipc:latest` which is ready to use.

## Building Custom Image (Optional)

Only build a custom image if you need to modify the CUDA IPC example code:

```bash
# from the repository root
docker build -t your-registry/cuda-ipc:latest -f kubernetes/Dockerfile .
docker push your-registry/cuda-ipc:latest
```

Then update the image references in `pods.yaml` to point to your custom image.

## Prerequisites

Ensure your Kubernetes cluster has:
- NVIDIA GPU support (NVIDIA device plugin installed)
- Nodes with NVIDIA GPUs available
- Container runtime that supports GPU access (containerd/docker with nvidia-container-runtime)

## Deploying Producer and Consumer Pods

Apply `kubernetes/pods.yaml` to start both pods on the same GPU node:

```bash
kubectl apply -f kubernetes/pods.yaml
```

## Key Configuration

- `hostIPC: true` is required to share CUDA IPC handles between pods
- `IPC_LOCK` capability is needed for CUDA IPC operations
- Both pods must run on the same node (enforced via nodeSelector)
- Each pod requests 1 GPU resource

## Monitoring

Check pod status and logs:

```bash
kubectl get pods
kubectl logs producer
kubectl logs consumer
```

## Cleanup

```bash
kubectl delete -f kubernetes/pods.yaml
```