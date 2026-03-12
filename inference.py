"""
Inference script for JetMassModel mass regression.

Usage:
    # Inference on a parquet file
    python inference.py --input top_gun_opendata_0_part_00000.parquet --checkpoint latest_checkpoint_file_201.pth

    # Inference on a single random sample (sanity check)
    python inference.py --checkpoint latest_checkpoint_file_201.pth --dummy

    # Inference using the ONNX model instead of PyTorch
    python inference.py --input top_gun_opendata_0_part_00000.parquet --onnx sample.onnx

    # Specify normalization stats (required to convert predictions back to original scale)
    python inference.py --input top_gun_opendata_0_part_00000.parquet --checkpoint latest_checkpoint_file_201.pth \
        --target-mean 293.3461 --target-std 119.9946

    # Save predictions to CSV
    python inference.py --input top_gun_opendata_0_part_00000.parquet --checkpoint latest_checkpoint_file_201.pth \
        --output predictions.csv
"""

import argparse
import os
import sys
import time
from glob import glob

import numpy as np
import torch
import torch.nn as nn



class ResidualBlock(nn.Module):
    def __init__(self, inplanes, planes, shortcut=None, downsample=False):
        super().__init__()
        self.stride = 2 if downsample else 1
        self.layer1 = nn.Conv2d(inplanes, planes, 3, self.stride, padding=1)
        self.activation = nn.ReLU()
        self.layer2 = nn.Conv2d(planes, planes, kernel_size=3, stride=1, padding=1)
        self.shortcut = shortcut
        self.norm1 = nn.BatchNorm2d(planes)
        self.norm2 = nn.BatchNorm2d(planes)

    def forward(self, x):
        shortcut = self.shortcut(x) if self.shortcut else 0
        x = self.layer1(x)
        x = self.norm1(x)
        x = self.activation(x)
        x = self.layer2(x)
        x = self.norm2(x)
        return self.activation(x + shortcut)


class Bottleneck(nn.Module):
    def __init__(self, inplanes, planes, downsample=False, shortcut=None):
        super().__init__()
        self.stride = 2 if downsample else 1
        self.layer1 = nn.Conv2d(inplanes, planes, 1, self.stride, padding=0)
        self.layer2 = nn.Conv2d(planes, planes, 3, 1, padding=1)
        self.layer3 = nn.Conv2d(planes, planes, 1, padding=0)
        self.shortcut = shortcut
        self.activation = nn.ReLU()
        self.norm1 = nn.BatchNorm2d(planes)
        self.norm2 = nn.BatchNorm2d(planes)

    def forward(self, x):
        shortcut = self.shortcut(x) if self.shortcut else 0
        x = self.layer1(x)
        x = self.norm1(x)
        x = self.activation(x)
        x = self.layer2(x)
        x = self.norm2(x)
        x = self.activation(x)
        x = self.layer3(x)
        return self.activation(x + shortcut)


class convnet(nn.Module):
    def __init__(self, layers: list, inplanes, expansion=2):
        super().__init__()
        self.no_blocks_in_layers = layers
        self.expansion = expansion
        self.inplanes = 64
        self.layer1 = nn.Sequential(
            nn.Conv2d(in_channels=inplanes, out_channels=64, kernel_size=3, stride=2, padding=2),
            nn.BatchNorm2d(64),
        )
        self.layers = nn.ModuleList()
        self.globalavgpool = nn.AdaptiveAvgPool2d((1, 1))
        self.build_layers()

    @property
    def no_of_layers(self):
        return len(self.no_blocks_in_layers)

    def make_layer_Res(self, no_of_blocks, planes, downsample):
        blocks = []
        if downsample:
            blocks.append(ResidualBlock(self.inplanes, planes, downsample=True,
                                        shortcut=nn.Conv2d(self.inplanes, planes, 1, 2)))
        for _ in range(no_of_blocks - 1):
            blocks.append(ResidualBlock(planes, planes, shortcut=nn.Identity()))
        self.inplanes = planes
        return nn.Sequential(*blocks)

    def make_layer_Botl(self, no_of_blocks, planes, downsample):
        blocks = []
        if downsample:
            blocks.append(Bottleneck(self.inplanes, planes, downsample=True,
                                     shortcut=nn.Conv2d(self.inplanes, planes, 1, 2)))
        for _ in range(no_of_blocks - 1):
            blocks.append(Bottleneck(planes, planes, shortcut=nn.Identity()))
        self.inplanes = planes
        return nn.Sequential(*blocks)

    def build_layers(self):
        blocks_count = 0
        total_blocks = sum(self.no_blocks_in_layers)
        bottleneck_threshold = total_blocks // 2 if total_blocks >= 24 else float('inf')

        for i in range(self.no_of_layers):
            if i == 0:
                self.layers.append(self.make_layer_Res(self.no_blocks_in_layers[i], self.inplanes, False))
                blocks_count += self.no_blocks_in_layers[i]
                continue
            if blocks_count < bottleneck_threshold:
                self.layers.append(self.make_layer_Res(self.no_blocks_in_layers[i],
                                                       self.inplanes * self.expansion, True))
            else:
                self.layers.append(self.make_layer_Botl(self.no_blocks_in_layers[i],
                                                        self.inplanes * self.expansion, True))
            blocks_count += self.no_blocks_in_layers[i]

    def forward(self, x):
        x = self.layer1(x)
        for layer in self.layers:
            x = layer(x)
        x = self.globalavgpool(x)
        return x


class JetMassModel(nn.Module):
    def __init__(self, layers, in_channels, expansion=1):
        super().__init__()
        self.backbone = convnet(layers=layers, inplanes=in_channels, expansion=expansion)
        self.feature_dim = self.backbone.inplanes
        self.head = nn.Linear(self.feature_dim, 1)

    def forward(self, x):
        x = self.backbone(x)
        x = torch.flatten(x, 1)
        x = self.head(x)
        return x



def _to_fixed_jet_array(x_item, target_channels=4, jet_h=125, jet_w=125):
    """Convert a single X_jet sample to a fixed (C,H,W) float32 array."""
    if hasattr(x_item, "as_py"):
        x_item = x_item.as_py()

    out = np.zeros((target_channels, jet_h, jet_w), dtype=np.float32)

    x = None
    try:
        x = np.asarray(x_item, dtype=np.float32)
    except (ValueError, TypeError):
        x = None

    if x is not None and x.dtype != object:
        if x.ndim == 2:
            x = x[np.newaxis, ...]
        if x.ndim == 3:
            c = min(x.shape[0], target_channels)
            h = min(x.shape[1], jet_h)
            w = min(x.shape[2], jet_w)
            out[:c, :h, :w] = x[:c, :h, :w]
            return out
        if x.ndim == 1 and x.size == jet_h * jet_w:
            out[0, :, :] = x.reshape(jet_h, jet_w)
            return out

    if isinstance(x_item, (list, tuple)) and len(x_item) > 0:
        for ch_idx in range(min(len(x_item), target_channels)):
            ch = x_item[ch_idx]
            if hasattr(ch, "as_py"):
                ch = ch.as_py()
            try:
                ch_arr = np.asarray(ch, dtype=np.float32)
            except (ValueError, TypeError):
                continue
            if ch_arr.dtype == object:
                continue
            if ch_arr.ndim == 1 and ch_arr.size == jet_h * jet_w:
                ch_arr = ch_arr.reshape(jet_h, jet_w)
            elif ch_arr.ndim > 2:
                ch_arr = np.squeeze(ch_arr)
                if ch_arr.ndim > 2:
                    ch_arr = ch_arr.reshape(-1, ch_arr.shape[-1])
            if ch_arr.ndim != 2:
                continue
            h = min(ch_arr.shape[0], jet_h)
            w = min(ch_arr.shape[1], jet_w)
            out[ch_idx, :h, :w] = ch_arr[:h, :w]

    return out


def load_parquet_data(file_path, target_channels=4):
    """Load X_jet (and optionally m) from a parquet file. Returns (tensor, masses|None)."""
    import pyarrow.parquet as pq

    pf = pq.ParquetFile(file_path)
    schema_names = [f.name for f in pf.schema_arrow]
    has_mass = "m" in schema_names
    columns = ["X_jet", "m"] if has_mass else ["X_jet"]

    jet_h, jet_w = 125, 125
    x_chunks = []
    m_chunks = []

    for batch in pf.iter_batches(columns=columns, batch_size=1024):
        x_vals = batch.column(0).to_pylist()
        n = len(x_vals)
        if n == 0:
            continue

        x_chunk = np.zeros((n, target_channels, jet_h, jet_w), dtype=np.float32)

        # Fast path
        x_all = None
        try:
            x_all = np.asarray(x_vals, dtype=np.float32)
        except (ValueError, TypeError):
            x_all = None

        if x_all is not None and x_all.ndim == 4 and x_all.dtype != object:
            c = min(x_all.shape[1], target_channels)
            h = min(x_all.shape[2], jet_h)
            w = min(x_all.shape[3], jet_w)
            x_chunk[:, :c, :h, :w] = x_all[:, :c, :h, :w]
        else:
            for i, item in enumerate(x_vals):
                x_chunk[i] = _to_fixed_jet_array(item, target_channels, jet_h, jet_w)

        x_chunks.append(x_chunk)

        if has_mass:
            m_vals = np.asarray(batch.column(1).to_numpy(zero_copy_only=False), dtype=np.float32)
            m_chunks.append(m_vals)

    x_tensor = torch.from_numpy(np.concatenate(x_chunks, axis=0))
    masses = np.concatenate(m_chunks) if m_chunks else None
    return x_tensor, masses


def _suggest_local_files(pattern, limit=5):
    matches = sorted(glob(pattern))
    if not matches:
        return ""
    lines = ["Available local matches:"]
    for match in matches[:limit]:
        lines.append(f"  - {match}")
    return "\n" + "\n".join(lines)


def _resolve_missing_input_file(file_path):
    if os.path.isfile(file_path):
        return file_path

    local_parquet_files = sorted(glob("*.parquet"))
    placeholder_names = {"data.parquet", "input.parquet", "sample.parquet"}
    if os.path.basename(file_path).lower() in placeholder_names and len(local_parquet_files) == 1:
        resolved = local_parquet_files[0]
        print(f"Input file '{file_path}' not found. Using local parquet file: {resolved}")
        return resolved

    return file_path


def _validate_input_file(file_path):
    file_path = _resolve_missing_input_file(file_path)
    if os.path.isfile(file_path):
        return file_path

    suggestion = _suggest_local_files("*.parquet")
    raise FileNotFoundError(
        f"Input parquet file not found: {file_path}\n"
        "Pass the real parquet filename to --input instead of the example placeholder."
        f"{suggestion}"
    )


def _validate_model_file(file_path, flag_name, pattern):
    if os.path.isfile(file_path):
        return

    suggestion = _suggest_local_files(pattern)
    raise FileNotFoundError(
        f"Model file not found for {flag_name}: {file_path}"
        f"{suggestion}"
    )



def run_pytorch_inference(model, x_tensor, device, batch_size=256):
    """Run inference with a PyTorch model. Returns numpy array of raw predictions."""
    model.eval()
    preds = []
    n = x_tensor.size(0)

    with torch.no_grad():
        for start in range(0, n, batch_size):
            end = min(start + batch_size, n)
            batch = x_tensor[start:end].to(device, non_blocking=True)
            out = model(batch).cpu().numpy()
            preds.append(out)

    return np.concatenate(preds, axis=0).squeeze(-1)


def run_onnx_inference(onnx_path, x_tensor, batch_size=256):
    """Run inference with an ONNX model via onnxruntime."""
    import onnxruntime as ort

    session = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    preds = []
    n = x_tensor.size(0)

    for start in range(0, n, batch_size):
        end = min(start + batch_size, n)
        batch_np = x_tensor[start:end].numpy()
        out = session.run(None, {input_name: batch_np})[0]
        preds.append(out)

    return np.concatenate(preds, axis=0).squeeze(-1)



def main():
    parser = argparse.ArgumentParser(description="JetMassModel Inference")

    # Input data
    parser.add_argument("--input", type=str, default=None,
                        help="Path to a parquet file with X_jet column")
    parser.add_argument("--dummy", action="store_true",
                        help="Run on a single random tensor (sanity check)")

    # Model source (pick one)
    parser.add_argument("--checkpoint", type=str, default=None,
                        help="Path to a .pth checkpoint file")
    parser.add_argument("--onnx", type=str, default=None,
                        help="Path to a .onnx model file")

    # Normalization stats (used during training; needed to denormalize predictions)
    parser.add_argument("--target-mean", type=float, default=293.3461,
                        help="Mean of the target 'm' used during training")
    parser.add_argument("--target-std", type=float, default=119.9946,
                        help="Std of the target 'm' used during training")

    # Output
    parser.add_argument("--output", type=str, default=None,
                        help="Save predictions to a CSV file")
    parser.add_argument("--batch-size", type=int, default=256,
                        help="Inference batch size (default: 256)")

    args = parser.parse_args()

    if args.checkpoint is None and args.onnx is None:
        parser.error("Provide either --checkpoint (PyTorch) or --onnx (ONNX Runtime)")
    if args.input is None and not args.dummy:
        parser.error("Provide --input <parquet_file> or --dummy for a sanity check")

    if not args.dummy:
        args.input = _validate_input_file(args.input)
    if args.checkpoint is not None:
        _validate_model_file(args.checkpoint, "--checkpoint", "*.pth")
    if args.onnx is not None:
        _validate_model_file(args.onnx, "--onnx", "*.onnx")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    true_masses = None
    if args.dummy:
        print("Running dummy inference on random input (1, 4, 125, 125)...")
        x_tensor = torch.randn(1, 4, 125, 125)
    else:
        print(f"Loading data from: {args.input}")
        x_tensor, true_masses = load_parquet_data(args.input)
        print(f"Loaded {x_tensor.size(0)} samples, shape: {tuple(x_tensor.shape)}")

    t0 = time.perf_counter()

    if args.onnx:
        print(f"Using ONNX model: {args.onnx}")
        raw_preds = run_onnx_inference(args.onnx, x_tensor, args.batch_size)
    else:
        print(f"Loading PyTorch checkpoint: {args.checkpoint}")
        model = JetMassModel(layers=[4, 6, 7, 6], in_channels=4, expansion=1).to(device)

        state = torch.load(args.checkpoint, map_location=device, weights_only=True)
        # Handle DataParallel-saved checkpoints
        clean_state = {k.replace("module.", ""): v for k, v in state.items()}
        model.load_state_dict(clean_state, strict=False)
        print("Checkpoint loaded.")

        raw_preds = run_pytorch_inference(model, x_tensor, device, args.batch_size)

    elapsed = time.perf_counter() - t0
    print(f"Inference completed in {elapsed:.3f}s ({x_tensor.size(0)} samples)")

    if args.target_mean is not None and args.target_std is not None:
        preds = raw_preds * args.target_std + args.target_mean
        print(f"Denormalized with mean={args.target_mean}, std={args.target_std}")
    else:
        preds = raw_preds
        if not args.dummy:
            print("Note: predictions are in normalized scale. "
                  "Pass --target-mean and --target-std to get original scale.")

    print(f"\nPredictions (first 10):")
    for i, p in enumerate(preds[:10]):
        line = f"  [{i}] predicted={p:.4f}"
        if true_masses is not None:
            line += f"  true={true_masses[i]:.4f}"
        print(line)

    if true_masses is not None and len(true_masses) > 0:
        if args.target_mean is not None and args.target_std is not None:
            mae = np.mean(np.abs(preds - true_masses))
            print(f"\nMAE (denormalized): {mae:.4f}")
        else:
            # Compare in normalized space
            safe_std = args.target_std if (args.target_std and abs(args.target_std) > 1e-12) else 1.0
            mean_val = args.target_mean if args.target_mean else 0.0
            norm_true = (true_masses - mean_val) / safe_std
            mae = np.mean(np.abs(raw_preds - norm_true))
            print(f"\nMAE (normalized): {mae:.4f}")

    print(f"\nSummary: min={preds.min():.4f}, max={preds.max():.4f}, "
          f"mean={preds.mean():.4f}, std={preds.std():.4f}")

    if args.output:
        import pandas as pd
        df = pd.DataFrame({"prediction": preds})
        if true_masses is not None:
            df["true_mass"] = true_masses
        df.to_csv(args.output, index=False)
        print(f"Predictions saved to: {args.output}")


if __name__ == "__main__":
    main()
