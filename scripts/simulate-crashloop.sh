#!/bin/bash
echo "Simulating CrashLoopBackOff..."
kubectl run crashloop-demo \
  --image=busybox \
  --namespace=demo-app \
  --restart=Always \
  -- sh -c "echo 'starting'; sleep 5; exit 1"
echo "Crashloop pod deployed. Watch pod restarts with: kubectl get pods -n demo-app -w"
