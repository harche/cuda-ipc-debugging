FROM nvidia/cuda:12.4.1-devel-ubuntu22.04
WORKDIR /workspace
COPY ipc_example /workspace/ipc_example
RUN nvcc ipc_example/example.cu -o /usr/local/bin/cuda-ipc-example && \
    ln -s /usr/local/bin/cuda-ipc-example /usr/local/bin/producer && \
    ln -s /usr/local/bin/cuda-ipc-example /usr/local/bin/consumer
ENTRYPOINT ["/bin/bash"]