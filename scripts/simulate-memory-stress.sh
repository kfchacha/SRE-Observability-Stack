#!/bin/bash
echo "Simulating memory pressure..."
kubectl run memory-stress \
  --image=polinux/stress \
  --namespace=demo-app \
  -- stress --vm 1 --vm-bytes 256M --timeout 300s
echo "Memory stress pod deployed. Watch Grafana memory dashboard."
