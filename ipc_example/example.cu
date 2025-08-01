// - process 1:
//  - ./example
//     -- if no shared memory handle is given
//        -  alloc gpu memory
//        -  create a shared memory handle
//        -  set gpu memory to 0
//        -  wait for other process to consume the data
//        -  ...
//        -  once data is consumed - exit
//
// - process 2:
// - ./example 0
//      - open shared memory handle 
//      - consume/modify data
//      - finish


// Parts taken from Nvidia's cuda-samples.

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <numeric>
#include <cstdlib>

#include <iostream>
#include <string>
#include <vector>


#define DATA_SIZE 1024 * 1024 // 1MB

typedef struct shmStruct_st
{
    cudaIpcMemHandle_t   memHandle;
    bool is_finished = false;
    bool handle_ready = false;
} shmStruct;

typedef struct sharedMemoryInfo_st {
    void *addr;
    size_t size;
    int shmFd;
} sharedMemoryInfo;


std::string const LSHM_NAME{"linux_shm"};

inline void __checkCUDAErrors(cudaError_t err, const char *file, const int line) {
#if defined(DEBUG) || defined(_DEBUG)
    cudaDeviceSynchronize(); // Ensure errors from async calls are caught
#endif
    if (err != cudaSuccess) {
        fprintf(stderr, "CUDA Runtime API error at %s:%d: %s.\n",
            file, line, cudaGetErrorString(err));
        exit(EXIT_FAILURE); // Or throw an exception
    }
}

#define checkCudaErrors(err) __checkCUDAErrors (err, __FILE__, __LINE__)

int sharedMemoryCreate(const char *name, size_t sz, sharedMemoryInfo *info) {
  int status = 0;

  info->size = sz;

  info->shmFd = shm_open(name, O_RDWR | O_CREAT, 0777);
  if (info->shmFd < 0) {
    return errno;
  }

  status = ftruncate(info->shmFd, sz);
  if (status != 0) {
    return status;
  }

  info->addr = mmap(0, sz, PROT_READ | PROT_WRITE, MAP_SHARED, info->shmFd, 0);
  if (info->addr == NULL) {
    return errno;
  }

  return 0;
}

int sharedMemoryOpen(const char *name, size_t sz, sharedMemoryInfo *info) {
  info->size = sz;

  info->shmFd = shm_open(name, O_RDWR, 0777);
  if (info->shmFd < 0) {
    return errno;
  }

  info->addr = mmap(0, sz, PROT_READ | PROT_WRITE, MAP_SHARED, info->shmFd, 0);
  if (info->addr == NULL) {
    return errno;
  }

  return 0;
}

void sharedMemoryClose(sharedMemoryInfo *info) {
  if (info->addr) {
    munmap(info->addr, info->size);
  }
  if (info->shmFd) {
    close(info->shmFd);
  }
}

void producer() {

    shmStruct* shm = nullptr;

    // Make linux shared memory to share cudaIPCHandle
    sharedMemoryInfo info;
    if (sharedMemoryCreate(LSHM_NAME.c_str(), sizeof(shmStruct), &info) != 0) {
        printf("Failed to create shared memory slab\n");
        exit(EXIT_FAILURE);
    }

    shm = (shmStruct *)info.addr;
    memset((void *)shm, 0, sizeof(*shm));

    void* ptr = nullptr;
    checkCudaErrors(cudaMalloc(&ptr, DATA_SIZE));
    checkCudaErrors(cudaIpcGetMemHandle((cudaIpcMemHandle_t *)&shm->memHandle, ptr));

    // set memory to zero in producer
    checkCudaErrors(cudaMemset(ptr, 0, DATA_SIZE));
    
    // Signal that the handle is ready for consumer
    shm->handle_ready = true;
    std::cerr<<"IPC handle ready, entering wait loop ...\n";
    while (!shm->is_finished) {
    }

    std::vector<int8_t> cpu_data(DATA_SIZE, 0);
    checkCudaErrors(cudaMemcpy(cpu_data.data(), ptr, DATA_SIZE, cudaMemcpyDeviceToHost));

    auto const cpu_data_sum = std::accumulate(cpu_data.begin(), cpu_data.end(), 0);
    std::cerr<<"cpu_data sum "<<cpu_data_sum<<std::endl;

    sharedMemoryClose(&info);
}

void consumer(int const id) {
    // id isn't used anywhere. it is simply used in `main` to determine which
    // function to execute (i.e. producer / consumer)

    sharedMemoryInfo info;
    shmStruct* shm = nullptr;

    if (sharedMemoryOpen(LSHM_NAME.c_str(), sizeof(shmStruct), &info) != 0) {
        printf("Failed to open shared memory slab\n");
        exit(EXIT_FAILURE);
    }
    shm = (shmStruct *)info.addr;
    
    // Wait for producer to create and signal the IPC handle is ready
    std::cerr<<"Waiting for IPC handle to be ready...\n";
    while (!shm->handle_ready) {
        usleep(1000); // Sleep 1ms
    }
    std::cerr<<"IPC handle ready, opening memory handle...\n";
    
    void* ptr = nullptr;
    checkCudaErrors(
            cudaIpcOpenMemHandle(&ptr, *(cudaIpcMemHandle_t *)&shm->memHandle, cudaIpcMemLazyEnablePeerAccess));

    cudaMemset(ptr, 1, DATA_SIZE);

    cudaDeviceSynchronize();
    shm->is_finished = true;
}

int main(int argc, char **argv)
{
    if (argc == 1) {
        producer();
    }
    else {
        consumer(atoi(argv[1]));
    }
    return EXIT_SUCCESS;
}
