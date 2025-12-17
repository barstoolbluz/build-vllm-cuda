{
  lib,
  stdenv,
  python3,
  fetchFromGitHub,
  cudaPackages ? null,
  darwin ? null,
  enableCuda ? stdenv.isLinux && cudaPackages != null,
}:

let
  version = "0.12.0";

  pythonWithPackages = python3.withPackages (ps: with ps; [
    setuptools
    wheel
    pip
    packaging
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
  ]);

in stdenv.mkDerivation rec {
  pname = "vllm-cuda";
  inherit version;

  src = fetchFromGitHub {
    owner = "vllm-project";
    repo = "vllm";
    rev = "v${version}";
    hash = "sha256-ioAgZZbMv99UudaHtb3KQFAdjJv9GqeNDXDAqQOIMN8=";
  };

  nativeBuildInputs = [
    pythonWithPackages
    pythonWithPackages.pkgs.ninja
    pythonWithPackages.pkgs.cmake
  ] ++ lib.optionals enableCuda (with cudaPackages; [
    cuda_nvcc
  ]);

  buildInputs = lib.optionals enableCuda (with cudaPackages; [
    cuda_cudart
    libcublas
    cuda_nvml_dev
    cudnn
  ]) ++ lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
    Accelerate
    CoreML
    Metal
  ]);

  # Environment variables for the build
  VLLM_TARGET_DEVICE = if enableCuda then "cuda" else "cpu";
  VLLM_BUILD_WITH_CUDA = if enableCuda then "1" else "0";
  VLLM_PYTHON_EXECUTABLE = "${pythonWithPackages}/bin/python";
  TORCH_CUDA_ARCH_LIST = lib.optionalString enableCuda "7.0;7.5;8.0;8.6;8.9;9.0";
  CUDA_HOME = lib.optionalString enableCuda "${cudaPackages.cuda_nvcc}";
  MAX_JOBS = if enableCuda then "8" else "4";

  buildPhase = ''
    runHook preBuild

    # Build the package
    ${pythonWithPackages}/bin/python setup.py build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Install the package
    ${pythonWithPackages}/bin/python setup.py install \
      --prefix=$out \
      --single-version-externally-managed \
      --root=/

    runHook postInstall
  '';

  # Skip tests as they require GPU
  doCheck = false;

  meta = with lib; {
    description = "High-throughput and memory-efficient inference engine for LLMs";
    homepage = "https://github.com/vllm-project/vllm";
    license = licenses.asl20;
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
  };
}