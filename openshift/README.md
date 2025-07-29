# OpenShift Deployment for CUDA IPC Example

This directory contains manifests and a Dockerfile for running the CUDA IPC
example on OpenShift using separate producer and consumer pods.

## Building the Image

```
# from the repository root
podman build -t quay.io/<user>/cuda-ipc:latest -f openshift/Dockerfile .
```

Push the image to your preferred registry:

```
podman push quay.io/<user>/cuda-ipc:latest
```

## Security Context Constraints

Create a custom `SecurityContextConstraints` allowing shared IPC and the
`IPC_LOCK` capability:

```bash
oc apply -f openshift/scc.yaml
oc create sa cuda-ipc-sa -n demo
oc adm policy add-scc-to-user cuda-ipc-scc -z cuda-ipc-sa -n demo
```

## Deploying Producer and Consumer Pods

Apply `openshift/pods.yaml` to start both pods on the same node:

```bash
oc apply -f openshift/pods.yaml
```

`hostIPC: true` is required to share CUDA IPC handles between the pods and avoid
"invalid device context" errors.
