#ifndef THC_GENERIC_FILE
#define THC_GENERIC_FILE "THC/generic/THCTensorMathReduce.cu"
#else

#if !defined(THC_REAL_IS_BOOL)

void THCTensor_(prod)(THCState* state, THCTensor *self, THCTensor *src, int dimension, int keepdim) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 2, self, src));
  if (!THC_reduceDim<scalar_t>(state, self, src,
                           thrust::identity<accreal>{},
                           ReduceMultiply<accreal>{},
                           thrust::identity<accreal>{},
                           scalar_cast<accreal>(1),
                           dimension,
                           keepdim)) {
    THArgCheck(false, 2, CUTORCH_DIM_WARNING);
  }

  THCudaCheck(cudaGetLastError());
}

#if defined(THC_REAL_IS_FLOAT) || defined(THC_REAL_IS_DOUBLE) || defined(THC_REAL_IS_HALF)

void THCTensor_(renorm)(THCState *state, THCTensor* self, THCTensor* src, scalar_t value, int dimension, scalar_t maxnorm)
{
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 2, self, src));
  dimension = at::maybe_wrap_dim(dimension, src);
  THArgCheck(dimension >= 0 && dimension < THCTensor_(nDimensionLegacyNoScalars)(state, src), 3, "invalid dimension");
  THArgCheck(THCNumerics<scalar_t>::gt(value, scalar_cast<scalar_t>(0)), 2, "non-positive-norm not supported");
  THArgCheck(THCTensor_(nDimensionLegacyNoScalars)(state, src) > 1, 1, "need at least 2 dimensions");

  THCTensor *self_;
  THCTensor *src_ = THCTensor_(newTranspose)(state, src, dimension, 0);
  THCTensor *data = THCTensor_(newClone)(state, src_);
  int64_t numel = THCTensor_(nElement)(state, data);

  if (numel > 0) {
    ptrdiff_t size = numel / THTensor_sizeLegacyNoScalars(data, 0);
    dim3 grid( THTensor_sizeLegacyNoScalars(data, 0));
    // NOTE: only with this specific number of threads can this work on GPUs with a warp size != 32 (such as AMD). Do not alter w/o changing buffer size in kernel.
    dim3 threads(32);

    THCTensor_kernel_renorm<scalar_t, accreal>
      <<<grid, threads, 0, c10::cuda::getCurrentCUDAStream()>>>
      (THCTensor_(data)(state, data), scalar_cast<accreal>(value), size, scalar_cast<accreal>(maxnorm));

    cudaError_t errcode = cudaGetLastError();
    if(errcode != cudaSuccess)
      THError(cudaGetErrorString(errcode));
  }

  THCTensor_(free)(state, src_);
  self_ = THCTensor_(newTranspose)(state, data, dimension, 0);
  THCTensor_(resizeAs)(state, self, self_);
  THCTensor_(freeCopyTo)(state, self_, self);
  THCTensor_(free)(state, data);
}

accreal THCTensor_(std_all)(THCState *state, THCTensor *self, bool unbiased)
{
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));
  return THCNumerics<accreal>::sqrt((THCTensor_(var_all)(state, self, unbiased)));
}

accreal THCTensor_(var_all)(THCState *state, THCTensor *self, bool unbiased)
{
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));
  accreal mean = THTensor_wrap(self).mean().item<accreal>();

  accreal val;
  if (!THC_reduceAll<scalar_t>(state, self,
                           SquareFunctor<accreal>(mean),
                           ReduceAdd<accreal>(),
                           scalar_cast<accreal>(0),
                           &val, 0)) {
    THArgCheck(false, 1, CUTORCH_DIM_WARNING);
  }

  val = THCNumerics<accreal>::div(
    val,
    scalar_cast<accreal>(std::max<int64_t>(0, THCTensor_(nElement)(state, self) - (unbiased ? 1 : 0)))
  );

  THCudaCheck(cudaGetLastError());
  return val;
}

#endif

#endif

#endif
