import torch
import triton

def print_separator():
    print("-" * 50)

def print_torch_info():
    print_separator()
    print("PyTorch Information")
    print_separator()
    print(f"Pytorch version           : {torch.__version__}")
    print(f"Pytorch detected GPU?     : {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        gpu_name = torch.cuda.get_device_name()
        print(f"Pytorch detected GPU name : {gpu_name}")
    else:
        print("No GPU detected by PyTorch.")

    print(f"Pytorch HIP version       : {torch.version.hip}")

def print_triton_info():
    print_separator()
    print("Triton Information")
    print_separator()
    print(f"Triton version            : {triton.__version__}")
    try:
        backend = triton.runtime.driver.active.get_current_target().backend
        print(f"Triton backend            : {backend}")
    except Exception as e:
        print("Failed to retrieve Triton backend information.")
        print(f"Error: {e}")

def test_tensor_operations():
    print_separator()
    print("Tensor Tests")
    print_separator()

    try:
        cpu_tensor = torch.tensor([1.0, 2.0, 3.0, 4.0], device="cpu")
        print(f"CPU Tensor: {cpu_tensor}")
        print(f"  is_cuda: {cpu_tensor.is_cuda}")

        if torch.cuda.is_available():
            gpu_tensor = torch.tensor([1.0, 2.0, 3.0, 4.0], device="cuda")
            print(f"GPU Tensor: {gpu_tensor}")
            print(f"  is_cuda: {gpu_tensor.is_cuda}")
        else:
            print("Skipping GPU tensor test (No GPU detected).")
    except Exception as e:
        print("Error during tensor operations.")
        print(f"Error: {e}")

def main():
    print_separator()
    print("System Check: PyTorch and Triton")
    print_separator()
    print_torch_info()
    print_triton_info()
    test_tensor_operations()
    print_separator()

if __name__ == "__main__":
    main()
