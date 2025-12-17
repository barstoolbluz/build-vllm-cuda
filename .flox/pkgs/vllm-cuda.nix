{
  lib,
  stdenv,
  python3Packages,
  fetchFromGitHub,
  cudaPackages ? null,
  darwin ? null,
  rocmPackages ? null,
  enableCuda ? stdenv.isLinux && cudaPackages != null,
  enableRocm ? false,
  enableCpu ? !enableCuda && !enableRocm,
}:

let
  version = "0.12.0";

  # Platform-specific dependencies
  platformDeps =
    if enableCuda then
      with cudaPackages; [
        cuda_nvcc
        cuda_cudart
        libcublas
        cuda_nvml_dev
        cudnn
      ]
    else if stdenv.isDarwin then
      with darwin.apple_sdk.frameworks; [
        Accelerate
        CoreML
        Metal
        MetalPerformanceShaders
        MetalPerformanceShadersGraph
      ]
    else
      [];

  # Build flags based on platform
  buildEnv =
    if enableCuda then {
      VLLM_TARGET_DEVICE = "cuda";
      TORCH_CUDA_ARCH_LIST = "7.0;7.5;8.0;8.6;8.9;9.0";
      CUDA_HOME = "${cudaPackages.cuda_nvcc}";
      VLLM_BUILD_WITH_CUDA = "1";
    } else {
      VLLM_TARGET_DEVICE = "cpu";
      VLLM_BUILD_WITH_CUDA = "0";
      MAX_JOBS = "4"; # Limit parallel jobs for CPU builds
    };

in python3Packages.buildPythonPackage rec {
  pname = "vllm-cuda";
  inherit version;

  src = fetchFromGitHub {
    owner = "vllm-project";
    repo = "vllm";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Will need to be filled in with actual hash
  };

  # Build-time dependencies
  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
    ninja
    cmake
    pybind11
  ] ++ lib.optionals enableCuda [
    cudaPackages.cuda_nvcc
  ];

  # Runtime dependencies
  propagatedBuildInputs = with python3Packages; [
    torch
    transformers
    tokenizers
    numpy
    pandas
    pyarrow
    fastapi
    uvicorn
    pydantic
    prometheus-client
    psutil
    ray
    sentencepiece
    tensorizer
    pynvml
    triton
    xformers
    outlines
    typing-extensions
    filelock
    aiohttp
    openai
    tiktoken
    lm-format-enforcer
    jinja2
    cloudpickle
    msgspec
    gguf
  ] ++ platformDeps;

  # Set build environment variables
  preBuild = ''
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${v}") buildEnv)}
  '';

  # Platform-specific patches
  patches = lib.optionals stdenv.isDarwin [
    # Patches for Darwin CPU-only build would go here
  ];

  # Disable tests that require GPU
  doCheck = false;

  # Additional setup for CPU-only builds
  postPatch = lib.optionalString enableCpu ''
    substituteInPlace setup.py \
      --replace "torch.cuda.is_available()" "False" \
      --replace "VLLM_TARGET_DEVICE = 'cuda'" "VLLM_TARGET_DEVICE = 'cpu'"
  '';

  pythonImportsCheck = [ "vllm" ];

  meta = with lib; {
    description = "High-throughput and memory-efficient inference engine for LLMs with CUDA/CPU support";
    homepage = "https://github.com/vllm-project/vllm";
    license = licenses.apache20;
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
    # Note which platforms have which features
    longDescription = ''
      vLLM inference engine with:
      - CUDA support on Linux (x86_64, aarch64)
      - CPU-only support on all Unix platforms
      - Experimental Metal support on Darwin (performance limited)
    '';
  };
}