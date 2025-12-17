# vLLM CUDA Build Environment

This Flox environment builds vLLM v0.12.0 with multi-platform support:
- **Linux (x86_64/aarch64)**: Full CUDA acceleration support
- **macOS (x86_64/aarch64)**: CPU-only fallback (Metal not yet supported by vLLM)

## Building

```bash
# Build the package
flox build vllm-cuda

# The built package will be available at ./result-vllm-cuda
```

## Publishing

```bash
# Publish to personal catalog for testing
flox publish vllm-cuda

# Or publish to organization catalog
flox publish -o myorg vllm-cuda
```

## Platform Support

| Platform | Acceleration | Status |
|----------|-------------|--------|
| x86_64-linux | CUDA | ✅ Full support |
| aarch64-linux | CUDA | ✅ Full support |
| x86_64-darwin | CPU | ⚠️ Fallback only |
| aarch64-darwin | CPU | ⚠️ Fallback only |

## Usage After Publishing

```toml
[install]
# Linux with CUDA
vllm.pkg-path = "username/vllm-cuda"
vllm.systems = ["x86_64-linux", "aarch64-linux"]

# macOS CPU fallback (if needed)
vllm-cpu.pkg-path = "username/vllm-cuda"
vllm-cpu.systems = ["x86_64-darwin", "aarch64-darwin"]
```

## Notes

- The Nix expression automatically detects the platform and builds accordingly
- CUDA support requires NVIDIA GPUs and is Linux-only
- macOS builds use CPU-only mode with `VLLM_TARGET_DEVICE=cpu`
- First build will need the source hash - run build once to get it, then update the hash in the .nix file