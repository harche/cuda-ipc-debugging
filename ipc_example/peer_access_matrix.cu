#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <numeric>

#include <iostream>
#include <string>
#include <vector>

int main(int argc, char **argv)
{

    int n_gpus = 8;
    for (int i = 0; i < n_gpus; ++i) {
      for (int j = 0; j < n_gpus; ++j) {
        int result = -1;
        cudaDeviceCanAccessPeer(&result, i, j);
        std::cerr<<"  - Can access peer "<<i<<", "<<j<<" : "<<result<<std::endl;
      }
    }

    return EXIT_SUCCESS;
}
