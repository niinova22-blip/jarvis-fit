"""Runs `python -m piper.train.export_onnx` with the TorchScript ONNX exporter.

PyTorch >= 2.9 defaults to the dynamo exporter (torch.export), which fails on the VITS spline flow's
`assert (discriminant >= 0).all()`. Piper does not pass `dynamo`, so we force the classic exporter here instead of
patching the GPL source.

    python export_onnx.py --checkpoint RUN/.../last.ckpt --output-file OUT/name.onnx
"""
import functools
import runpy
import sys

import torch

torch.onnx.export = functools.partial(torch.onnx.export, dynamo=False)
sys.argv = ["piper.train.export_onnx", *sys.argv[1:]]
runpy.run_module("piper.train.export_onnx", run_name="__main__", alter_sys=True)
