#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#include <string.h>
#include "cuda.h"

#define BLOCK_SIZE 128
#define NUM_ELEMENTS_PER_THREAD 1024

typedef unsigned char uchar;
typedef unsigned int uint;
typedef unsigned long ulong;

__global__ void consolidateHistogram(ulong*blockHistograms,ulong* cudaHistogram,uint numBlocks) {
    int tid = threadIdx.x;

    for (uint j=0;j<numBlocks;j++) {
        cudaHistogram[tid]+=blockHistograms[j*256+tid];
    }    
}

__global__ void calculateHistogram(uchar* data,ulong* blockHistograms,ulong N) {
    int tid = threadIdx.x;
    int x = threadIdx.x+blockIdx.x*blockDim.x;

    if (x<N) {
        __shared__ int sHistogram[512];

        int blockSize = 512/BLOCK_SIZE;
        int startIndex = tid*blockSize;
        int endIndex = startIndex+blockSize;
        if (tid==BLOCK_SIZE-1)
            endIndex+= 512%BLOCK_SIZE;

        for (int i=startIndex;i<endIndex;i++)
            sHistogram[i] = 0;
        
        __syncthreads();

        int index = x;
        for (int i=0;i<NUM_ELEMENTS_PER_THREAD;i++) {
            if (index>=N)
                break;
            int offset = 256*(threadIdx.x%2);
            atomicAdd(&sHistogram[offset+data[index]],1);
            index+=BLOCK_SIZE;
        }

        __syncthreads();

        int offset = 256*blockIdx.x;
        for (int i=startIndex;i<endIndex;i++) {
            blockHistograms[offset+(i%256)]+=sHistogram[i];
        }
    }
}

void validate(ulong* arr1,ulong* arr2) {
    uchar incorrectCount = 0;
    for (int i=0;i<256;i++) {
        if (arr1[i]!=arr2[i])
            incorrectCount++;
    }

    if (incorrectCount==0)
        printf("Passed validation\n");
    else
        printf("%u bins were incorrect\n",incorrectCount);
}

int main(int argc,char** argv) {
    ulong DATA_SIZE  = 1 << 28;
    srand(2019);
    uchar* data = (uchar*) malloc(DATA_SIZE);
    
    for (uint i=0;i<DATA_SIZE;i++) {
        data[i] = rand()%256;
    }

    double serialDuration = -1;
    double start = omp_get_wtime();
    ulong serialHistogram[256];
    memset(serialHistogram,0,sizeof(ulong)*256);
    for (uint i=0;i<DATA_SIZE;i++ ) {
        serialHistogram[data[i]]++;
    }
    double end = omp_get_wtime();
    serialDuration = end - start;
    printf("Serial operation took %.5f seconds to run.Speed up -\n",serialDuration);

    double parallelDuration = -1;
    start = omp_get_wtime();
    ulong parallelHistogram[256];
    memset(parallelHistogram,0,sizeof(ulong)*256);

    #pragma omp parallel
    {
        ulong partialHistogram[256];
        memset(partialHistogram,0,sizeof(ulong)*256);
        int numThreads = omp_get_num_threads();
        int tid = omp_get_thread_num();
        ulong blockSize = DATA_SIZE/numThreads;
        ulong startIndex = blockSize*tid;
        ulong endIndex = startIndex+blockSize;

        if (tid == numThreads-1)
            endIndex+= DATA_SIZE%numThreads;
        
        for (ulong i=startIndex;i<endIndex;i++) {
            partialHistogram[data[i]]++;
        }

        for (int i=0;i<256;i++) {
            #pragma omp critical
            {
                parallelHistogram[i]+=partialHistogram[i];
            }
        }
    }

    end = omp_get_wtime();
    parallelDuration = end-start;
    printf("Parallel operation took %.5f seconds to run. Speed up %.1f\n",parallelDuration,serialDuration/parallelDuration);

    validate(serialHistogram,parallelHistogram);

    double cudaDuration = -1;
    start = omp_get_wtime();
    ulong* cudaHistogram = (ulong*) malloc(sizeof(ulong)*256);
    memset(cudaHistogram,0,sizeof(ulong)*256);
    uint numBlocks = (DATA_SIZE+BLOCK_SIZE*NUM_ELEMENTS_PER_THREAD)/ (BLOCK_SIZE*NUM_ELEMENTS_PER_THREAD);
    ulong* blockHistograms = (ulong*) malloc(sizeof(ulong)*numBlocks*256);
    for (int i=0;i<numBlocks*256;i++)
        blockHistograms[i] = 0;

    struct CudaContext cudaContext;
    cudaContext.init();

    ulong* deviceBlockHistogram = (ulong*)cudaContext.cudaInOut((void*) blockHistograms,sizeof(ulong)*numBlocks*256);

    calculateHistogram<<<numBlocks,BLOCK_SIZE>>>(
        (uchar*)cudaContext.cudaIn((void*) data,sizeof(uchar)*DATA_SIZE),
        deviceBlockHistogram,
        DATA_SIZE);

    consolidateHistogram<<<1,256>>>(
        deviceBlockHistogram,
        (ulong*) cudaContext.cudaInOut((void*) cudaHistogram,sizeof(ulong)*256),
        numBlocks);

    cudaContext.synchronize((void*)cudaHistogram);

    end = omp_get_wtime();
    cudaDuration = end-start;
    printf("Cuda operation took %.5f seconds to run. Speed up %.1f\n",cudaDuration,serialDuration/cudaDuration);

    validate(serialHistogram,cudaHistogram);
    free(data);
    cudaContext.dispose();

    return 0;
}