# CMS Mass Regression: Deep Learning Pipeline

## Overview

This project implements an efficient deep learning pipeline for particle mass regression using CMS detector datasets. The work focuses on optimizing data loading, model training, and ensemble prediction for scientific regression tasks involving large-scale, high-dimensional data.

## Key Results

### Efficient Dataset Pipeline

- Developed a preprocessing pipeline to convert CMS detector data from Parquet format into dense tensor representations.
- Achieved efficient data streaming and batching, minimizing CPU overhead and improving GPU utilization.
- Dataset was reorganized into 140 shards (7,552 events each), reducing memory pressure and enabling scalable, shard-based training.

### Deep Learning Models

- Implemented and trained multiple deep learning models for mass regression:
  - **ResNet-based convolutional architectures**
  - **Vision Transformers (ViT)**
  - **Particle Transformer (ParT) inspired models**
- Explored hybrid and ensemble strategies to improve prediction robustness and accuracy.

### Training and Optimization

- Used AdamW and Sharpness-Aware Minimization (SAM) for stable and robust optimization.
- Applied z-score normalization to regression targets, significantly improving training stability and convergence.

### Experimental Results

#### Shard-Based Training

- Training on individual shards showed consistent loss reduction:
  - Example (Shard 135): Loss reduced from 0.5881 to 0.1322 in 5 epochs.
  - Similar trends observed for other shards (see logs below).
- Transitioning between shards revealed distribution shifts, motivating further improvements in data pipeline design.

#### Training Logs (Sample)

```
Shard 135:
Epoch 1/5 Training Loss: 0.5881
Epoch 2/5 Training Loss: 0.4300
Epoch 3/5 Training Loss: 0.2876
Epoch 4/5 Training Loss: 0.1909
Epoch 5/5 Training Loss: 0.1322

Shard 136:
Epoch 1/5 Training Loss: 0.5905
Epoch 2/5 Training Loss: 0.4194
Epoch 3/5 Training Loss: 0.3025
Epoch 4/5 Training Loss: 0.1916
Epoch 5/5 Training Loss: 0.1209

Shard 137:
Epoch 1/5 Training Loss: 0.5505
Epoch 2/5 Training Loss: 0.3965
Epoch 3/5 Training Loss: 0.2801
Epoch 4/5 Training Loss: 0.1793
Epoch 5/5 Training Loss: 0.1256
```

#### Data Loading Performance

- Initial dataset formation: ~609 seconds for full Parquet parsing and tensor materialization.
- Per-sample retrieval after construction: ~0.0059 seconds.
- Highlighted the need for improved data streaming to reduce startup latency.

### Ensemble Prediction

- Combined predictions from multiple architectures using averaging and weighted strategies.
- Ensemble models demonstrated improved regression accuracy and stability over individual models.

### Integration and Reproducibility

- All code, data processing scripts, and training pipelines are version-controlled and documented for reproducibility.
- Trained models are exportable to ONNX/TorchScript for integration with the CMS Software (CMSSW) inference framework.


## Problems Addressed


This project tackles a wide range of technical and scientific challenges in applying deep learning to large-scale, high-dimensional physics data:

- **Inefficient Data Loading:** CMS detector data in Parquet format contains nested arrays, requiring expensive decoding and reconstruction for each training batch. This leads to high data loading overhead, long startup times, and low GPU utilization.
- **Scalability Issues:** Large file sizes and complex data structures cause memory pressure, inconsistent batch times, and interruptions during long training runs. The need to split data into manageable shards and optimize memory usage is critical for practical training.
- **Training Instability:** Without proper normalization (e.g., z-score normalization of regression targets) and efficient data streaming, model training can become unstable, slow to converge, or even diverge.
- **Distribution Shifts:** Shard-based training can introduce distribution shifts between batches, disrupting optimization and reducing model performance across the full dataset. Ensuring continuity and consistency across shards is a key challenge.
- **Integration Barriers:** Bridging the gap between scientific data formats (Parquet, ROOT) and deep learning frameworks (PyTorch), and ensuring models are exportable (ONNX, TorchScript) for use in the CMS Software (CMSSW) ecosystem.
- **Optimization Complexity:** Selecting and tuning advanced optimizers (AdamW, SAM), learning rate schedules, and batch sizes to achieve robust and generalizable model performance.
- **Model Architecture Selection:** Evaluating and comparing different deep learning architectures (ResNet, Vision Transformer, Particle Transformer) and their suitability for regression on detector images.
- **Ensemble Learning:** Designing ensemble strategies to combine predictions from multiple models, improving accuracy and robustness in the presence of noisy or complex data.
- **Reproducibility and Documentation:** Ensuring all experiments, pipelines, and results are reproducible, well-documented, and version-controlled for future research and collaboration.
- **Resource Constraints:** Managing limited compute and storage resources, optimizing for available RAM and GPU capacity, and enabling efficient experimentation.

The solutions developed in this project directly address these problems, enabling efficient, scalable, and robust deep learning for particle mass regression and providing a foundation for future scientific machine learning workflows.

## References

- He et al., "Deep Residual Learning for Image Recognition" (CVPR 2016)
- Dosovitskiy et al., "An Image is Worth 16x16 Words: Transformers for Image Recognition at Scale" (ICLR 2021)
- Qu et al., "Particle Transformer for Jet Tagging" (ICML 2022)
- See proposal for full bibliography.
