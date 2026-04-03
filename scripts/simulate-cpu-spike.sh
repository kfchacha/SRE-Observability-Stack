#!/bin/bash
echo "Simulating CPU spike..."
kubectl run cpu-stress \
  --image=containerstack/cpustress \
  --namespace=demo-app \
  -- --cpu 4 --timeout 300s --metrics-brief
echo "CPU stress pod deployed. Watch Prometheus alerts at localhost:9090"
