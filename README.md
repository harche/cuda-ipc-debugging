
At the moment, cuda-ipc works (refer to README.md in  ipc_example), only when
the `privilege` option is set to "true" in values.yaml.

The goal is to have cuda-ipc working without such elevated privileges.

Note:
If using privilege=true, use,
`source which_gpu.sh` with in the pods to determine which gpu is allocated to the pod and 
restrict the pod to that GPU using `CUDA_VISIBLE_DEVICES`
