{
  lib,
  stdenv,
  python3Packages,
  fetchFromGitHub,
  git,
  cmake,
  ninja,
  cudaPackages ? null,
  darwin ? null,
  enableCuda ? stdenv.isLinux && cudaPackages != null,
}:

let
  version = "0.12.0";

  # Pre-fetch the cutlass dependency
  cutlass = fetchFromGitHub {
    owner = "nvidia";
    repo = "cutlass";
    rev = "bf9da7b76c766d7ee7d536afc77880a4ef1f1156";  # v3.6.0
    hash = "sha256-FbMVqR4eZyum5w4Dj5qJgBPOS66sTem/qKZjYIK/7sg=";
  };

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

in python3Packages.buildPythonPackage rec {
  pname = "vllm-cuda";
  inherit version;

  # Use new Python packaging format
  pyproject = true;

  src = fetchFromGitHub {
    owner = "vllm-project";
    repo = "vllm";
    rev = "v${version}";
    hash = "sha256-ioAgZZbMv99UudaHtb3KQFAdjJv9GqeNDXDAqQOIMN8=";
  };

  # Patch to use pre-fetched cutlass
  postPatch = ''
    # Replace the FetchContent with our pre-fetched version
    substituteInPlace CMakeLists.txt \
      --replace "FetchContent_Declare(
        cutlass
        GIT_REPOSITORY https://github.com/nvidia/cutlass.git" \
      "FetchContent_Declare(
        cutlass
        SOURCE_DIR ${cutlass}" \
      --replace "GIT_TAG" "# GIT_TAG" \
      --replace "GIT_PROGRESS TRUE" "# GIT_PROGRESS TRUE"
  '';

  # Build system dependencies
  build-system = with python3Packages; [
    setuptools
    wheel
    scikit-build-core
  ];

  # Build-time dependencies
  nativeBuildInputs = [
    git
    cmake
    ninja
    python3Packages.pybind11
    python3Packages.packaging
  ] ++ lib.optionals enableCuda [
    cudaPackages.cuda_nvcc
    cudaPackages.cuda_cudart
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
    pynvml
    triton
    typing-extensions
    filelock
    aiohttp
    openai
    tiktoken
    jinja2
    cloudpickle
  ] ++ platformDeps;

  # Environment variables
  env = {
    VLLM_TARGET_DEVICE = if enableCuda then "cuda" else "cpu";
    VLLM_BUILD_WITH_CUDA = if enableCuda then "1" else "0";
    VLLM_PYTHON_EXECUTABLE = "${python3Packages.python.interpreter}";
    TORCH_CUDA_ARCH_LIST = lib.optionalString enableCuda "7.0;7.5;8.0;8.6;8.9;9.0";
    CUDA_HOME = lib.optionalString enableCuda "${cudaPackages.cuda_nvcc}";
  };

  # CMake flags
  cmakeFlags = [
    "-DVLLM_PYTHON_EXECUTABLE=${python3Packages.python.interpreter}"
    "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
    "-DFETCHCONTENT_SOURCE_DIR_CUTLASS=${cutlass}"
  ] ++ lib.optionals enableCuda [
    "-DCMAKE_CUDA_COMPILER=${cudaPackages.cuda_nvcc}/bin/nvcc"
    "-DCUDA_TOOLKIT_ROOT_DIR=${cudaPackages.cuda_nvcc}"
  ];

  # Disable tests that require GPU
  doCheck = false;

  pythonImportsCheck = [ "vllm" ];

  meta = with lib; {
    description = "High-throughput and memory-efficient inference engine for LLMs";
    homepage = "https://github.com/vllm-project/vllm";
    license = licenses.asl20;
    platforms = platforms.unix;
  };
}