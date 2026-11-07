"""Halves a Piper ONNX voice by storing its float weights as float16 (venv .venv-piper).

Compute stays float32: every converted weight gets a Cast back to float32, which ONNX Runtime folds once when the
session is created. That keeps the model on the plain CPU kernels the iOS app uses (no float16 operators needed); the
only change is float16 rounding of the weights.

    python shrink_onnx.py IN.onnx OUT.onnx

Afterwards it runs both models without randomness (noise scales 0) on a few phoneme sequences and prints the
signal-to-error ratio of the new output against the original.
"""
import sys

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

src, dst = sys.argv[1], sys.argv[2]
model = onnx.load(src)
graph = model.graph
casts, converted = [], set()
for init in graph.initializer:
    if init.data_type != TensorProto.FLOAT or int(np.prod(init.dims)) < 256:
        continue
    weights = numpy_helper.to_array(init)
    if np.abs(weights).max() > 60000:  # would overflow float16
        continue
    name = init.name
    init.CopyFrom(numpy_helper.from_array(weights.astype(np.float16), name + "__fp16"))
    casts.append(helper.make_node("Cast", [name + "__fp16"], [name], to=TensorProto.FLOAT, name=name + "__cast"))
    converted.add(name)

nodes = casts + list(graph.node)
del graph.node[:]
graph.node.extend(nodes)
inputs = [i for i in graph.input if i.name not in converted]
del graph.input[:]
graph.input.extend(inputs)
onnx.checker.check_model(model)
onnx.save(model, dst)
print(f"converted {len(converted)} weights")

import os  # noqa: E402

import onnxruntime as ort  # noqa: E402

print(f"size {os.path.getsize(src) / 1e6:.1f} MB -> {os.path.getsize(dst) / 1e6:.1f} MB")
a = ort.InferenceSession(src, providers=["CPUExecutionProvider"])
b = ort.InferenceSession(dst, providers=["CPUExecutionProvider"])
rng = np.random.default_rng(0)
scales = np.array([0.0, 1.0, 0.0], dtype=np.float32)
ratios = []
for length in (40, 90, 160):
    ids = rng.integers(3, 60, size=length).astype(np.int64)
    ids[1::2] = 0  # Piper layout: phoneme, pad, phoneme, pad...
    ids = np.concatenate([[1, 0], ids, [2]]).astype(np.int64)[None, :]
    feed = {"input": ids, "input_lengths": np.array([ids.shape[1]], dtype=np.int64), "scales": scales}
    ya, yb = a.run(None, feed)[0].squeeze(), b.run(None, feed)[0].squeeze()
    n = min(len(ya), len(yb))
    ratios.append(10 * np.log10(np.sum(ya[:n] ** 2) / max(np.sum((ya[:n] - yb[:n]) ** 2), 1e-12)))
    print(f"len {length}: samples {len(ya)} vs {len(yb)}, signal/error {ratios[-1]:.1f} dB")
print(f"min signal/error {min(ratios):.1f} dB")
