{
  lib,
  stdenv,
  python3Packages,
  fetchFromGitHub,
  fetchurl,
  git,
  cmake,
  ninja,
  cudaPackages ? null,
  darwin ? null,
  enableCuda ? stdenv.isLinux && cudaPackages != null,
}:

let
  version = "0.12.0";

  # First, create a fixed-output derivation to fetch all dependencies
  vllmDeps = stdenv.mkDerivation {
    pname = "vllm-deps";
    inherit version;

    src = fetchFromGitHub {
      owner = "vllm-project";
      repo = "vllm";
      rev = "v${version}";
      hash = "sha256-ioAgZZbMv99UudaHtb3KQFAdjJv9GqeNDXDAqQOIMN8=";
    };

    nativeBuildInputs = [
      git
      cmake
      ninja
      python3Packages.python
      python3Packages.pip
      python3Packages.wheel
      python3Packages.setuptools
      python3Packages.packaging
    ] ++ lib.optionals enableCuda [
      cudaPackages.cuda_nvcc
    ];

    # This is a fixed-output derivation that fetches dependencies
    outputHashMode = "recursive";
    outputHash = "sha256-0000000000000000000000000000000000000000000="; # Will need to be updated

    # Environment variables
    VLLM_TARGET_DEVICE = if enableCuda then "cuda" else "cpu";
    VLLM_BUILD_WITH_CUDA = if enableCuda then "1" else "0";
    VLLM_PYTHON_EXECUTABLE = "${python3Packages.python.interpreter}";
    TORCH_CUDA_ARCH_LIST = lib.optionalString enableCuda "7.0;7.5;8.0;8.6;8.9;9.0";
    CUDA_HOME = lib.optionalString enableCuda "${cudaPackages.cuda_nvcc}";

    buildPhase = ''
      # Create a directory for dependencies
      mkdir -p $out/deps

      # Configure cmake to download dependencies
      cmake -B build \
        -DVLLM_PYTHON_EXECUTABLE=$VLLM_PYTHON_EXECUTABLE \
        -DVLLM_TARGET_DEVICE=$VLLM_TARGET_DEVICE \
        -DCMAKE_BUILD_TYPE=Release \
        -DFETCHCONTENT_BASE_DIR=$out/deps \
        -DFETCHCONTENT_QUIET=OFF \
        ${lib.optionalString enableCuda "-DCMAKE_CUDA_COMPILER=${cudaPackages.cuda_nvcc}/bin/nvcc"}

      # Run the configure step to trigger downloads
      cmake --build build --target help || true

      # Also download Python dependencies
      ${python3Packages.python.interpreter} -m pip download \
        --no-deps \
        --dest $out/python-deps \
        . || true

      # Save the source as well
      cp -r . $out/source
    '';

    installPhase = ''
      # Everything is already in $out from buildPhase
      echo "Dependencies fetched to $out"
    '';

    # Allow network access for this derivation
    __noChroot = true;
  };

  # Now the main build that uses the pre-fetched dependencies
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

  # Build system dependencies
  build-system = with python3Packages; [
    setuptools
    wheel
    scikit-build-core
  ];

  # Build-time dependencies
  nativeBuildInputs = [
    git
    stdenv.cc
    cmake
    ninja
    python3Packages.pybind11
    python3Packages.packaging
  ] ++ lib.optionals enableCuda [
    cudaPackages.cuda_nvcc
    cudaPackages.cuda_nvcc.dev or cudaPackages.cuda_nvcc
    cudaPackages.cuda_cudart
  ];

  # Runtime dependencies
  propagatedBuildInputs = with python3Packages; [
    (if enableCuda then (torchWithCuda or torch) else torch)
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
  ] ++ lib.optionals enableCuda (with cudaPackages; [
    cuda_cudart
    libcublas
    cuda_nvml_dev
    cudnn
  ]) ++ lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
    Accelerate
    CoreML
    Metal
    MetalPerformanceShaders
    MetalPerformanceShadersGraph
  ]);

  # Environment variables
  VLLM_TARGET_DEVICE = if enableCuda then "cuda" else "cpu";
  VLLM_BUILD_WITH_CUDA = if enableCuda then "1" else "0";
  VLLM_PYTHON_EXECUTABLE = "${python3Packages.python.interpreter}";
  TORCH_CUDA_ARCH_LIST = lib.optionalString enableCuda "7.0;7.5;8.0;8.6;8.9;9.0";
  CUDA_HOME = lib.optionalString enableCuda "${cudaPackages.cuda_nvcc}";

  # CMake flags
  cmakeFlags = [
    "-DVLLM_PYTHON_EXECUTABLE=${python3Packages.python.interpreter}"
    "-DFETCHCONTENT_SOURCE_DIR_CUTLASS=${vllmDeps}/deps/cutlass-src"
    "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
  ] ++ lib.optionals enableCuda [
    "-DCMAKE_CUDA_COMPILER=${cudaPackages.cuda_nvcc}/bin/nvcc"
    "-DCUDA_TOOLKIT_ROOT_DIR=${cudaPackages.cuda_nvcc}"
  ];

  preBuild = ''
    # Copy pre-fetched dependencies
    if [ -d "${vllmDeps}/deps" ]; then
      cp -r ${vllmDeps}/deps/* ./_deps/ || true
    fi
  '';

  # Disable tests that require GPU
  doCheck = false;

  # Additional setup for CPU-only builds
  postPatch = lib.optionalString (!enableCuda) ''
    substituteInPlace setup.py \
      --replace "torch.cuda.is_available()" "False" \
      --replace "VLLM_TARGET_DEVICE = 'cuda'" "VLLM_TARGET_DEVICE = 'cpu'"
  '';

  pythonImportsCheck = [ "vllm" ];

  meta = with lib; {
    description = "High-throughput and memory-efficient inference engine for LLMs with CUDA/CPU support";
    homepage = "https://github.com/vllm-project/vllm";
    license = licenses.asl20;
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
  };
}