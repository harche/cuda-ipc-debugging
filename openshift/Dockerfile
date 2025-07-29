FROM nvidia/cuda:12.4.1-devel-ubuntu22.04
WORKDIR /workspace
COPY ../ipc_example /workspace/ipc_example
RUN nvcc ipc_example/producer.cu -o /usr/local/bin/producer && \
    nvcc ipc_example/consumer.cu -o /usr/local/bin/consumer
ENTRYPOINT ["/bin/bash"]
