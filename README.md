## Representative Training Logs and Timings

### Shard-Based Training Logs

| Shard | Initial Loss | Final Loss | Epochs |
|-------|--------------|------------|--------|
| 135   | 0.5881       | 0.1322     | 5      |
| 136   | 0.5905       | 0.1209     | 5      |
| 137   | 0.5505       | 0.1256     | 5      |

These logs show consistent loss reduction within each shard, but also highlight the loss spike when moving between shards.

### Dataset Loading Timings

- **Dataset formation time:** 609.33 seconds (full Parquet parsing and tensor materialization)
- **First sample:** x shape = torch.Size([4, 125, 125]), y = 201.67
- **Access time for one item:** 0.00588 seconds

While per-sample retrieval is fast after construction, the initial dataset formation step is expensive and impacts iterative development and GPU utilization.
## Problems Encountered

During the development and experimentation process, several key challenges were identified:

- **Large File Loading Overhead:** The original large, nested Parquet files caused high data loading overhead, inconsistent batch preparation times, and interruptions during long training runs. This made efficient GPU utilization difficult and slowed down experimentation.

- **Distribution Shifts Between Shards:** When training progressed from one shard to the next, a spike in training loss was often observed. This suggests that the current shard-based loading strategy may introduce distribution shifts or disrupt optimization continuity, making it harder for the model to generalize across the full dataset.

- **Unstable Training Without Target Normalization:** Training without z-score normalization of the regression target led to instability and unreliable convergence. Normalization was found to be essential for stable and effective training.

- **Expensive Dataset Initialization:** The initial dataset formation step (full Parquet parsing and tensor materialization) was slow, taking several minutes. This high startup latency reduced the efficiency of iterative model development and hyperparameter tuning.

These problems motivated the adoption of shard-based training, mandatory target normalization, and ongoing work to further optimize the data pipeline for scalable, efficient deep learning on large scientific datasets.

# Deep Learning Inference for Mass Regression

This repository implements a deep learning pipeline for mass regression using CMS detector data in Parquet format. The workflow and model details are based directly on the provided Jupyter notebooks.

## Features

- **ConvNet architecture** with Batch Normalization in the first layer
- **Z-score normalization** of target labels
- **Training loop** that iterates over Parquet files
- **Learning rate scheduler** that decays by 0.9 after each file
- **PyTorch DataLoader** and custom Dataset for efficient data handling

## Data Pipeline

The pipeline loads CMS detector data from Parquet files, converts them into dense tensor representations, and normalizes the regression targets. The data loader supports chunked reading and handles ragged/nested arrays robustly.

## Model

The main model is a convolutional neural network (ConvNet) with support for 4-channel input images (jets). The model is trained using MSE loss and Adam optimizer. Training and validation are performed file-by-file, with checkpoints saved after each file.

## Training

1. Compute global mean and std for the regression target (`m`) using only training files.
2. For each Parquet file:
    - Load data and normalize targets
    - Train for N epochs (default: 30)
    - Save checkpoint after each file
3. Optionally, validate on held-out files using the same normalization.

## Usage

1. Place your Parquet files in the appropriate directory.
2. Run the training notebook or script to start training.
3. Checkpoints will be saved as `latest_checkpoint_file_X.pth`.
4. Use the validation function to evaluate model performance on new files.

## Requirements

See `requirements.txt` for dependencies. Main libraries: PyTorch, numpy, pandas, pyarrow.

## Example: Training Loop (from notebook)

```python
for file_idx, file_path in enumerate(train_files):
    train_on_file(file_idx, file_path, epochs=30)
```

## Example: Validation (from notebook)

```python
validate_on_file("/path/to/heldout_file.parquet")
```

## Notes

- All code, data processing, and training logic are in the notebooks.
- No proposal or extraneous content is included in this README.

---
This README is written from the workflow and documentation in the project notebooks.
