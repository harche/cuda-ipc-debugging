compilation:

nvcc example.cu -o example

run:

process1: ./example

process2: ./example 0

Expectation:
 
 time  process1                          process2 
  |      |                                  x
  |    allocate memory                      x
  |      |                                  x
  |    set up ipc handle with               x
  |    cudaIpcGetMemHandle to               x
  |    share that memory                    x
  |      |                                  x
  |    set all values in memory             x
  |    to 0.                                x   
  |      |                                  x 
  |      |                                  x
  |     wait                                x
  |      |                                  |
  |      |                                  |
  |      |                               grabs the shared memory
  |      |                              using cudaIpcOpenMemHandle
  |      |                                  |
  |      |                              set all values in shared memory
  |      |                              to 1. mark completion and exit
  |      |                                  |
  |      |                                  x
  |   compute memory sum
  |   print and exit
  |      |
  |      x
  V                                         
