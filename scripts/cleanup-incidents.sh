#!/bin/bash
echo "Cleaning up incident simulation pods..."
kubectl delete pod cpu-stress memory-stress crashloop-demo -n demo-app --ignore-not-found
echo "Done. Alerts should return to Inactive within 5 minutes."
