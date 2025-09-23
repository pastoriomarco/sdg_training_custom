import onnx, sys
m = onnx.load(f"{sys.argv[1]}")
print("Inputs:", [i.name for i in m.graph.input])
print("Outputs:", [o.name for o in m.graph.output])