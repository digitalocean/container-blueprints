helm install digital-mobius digital-mobius/digital-mobius --version 0.1.4 \
  --set environmentVariables.DIGITAL_OCEAN_TOKEN="dop_v1_def3b2b462f8ea907f84ebbce661fb50ce7b89233a728e6ac4ae02917683aec7" \
  --set environmentVariables.DIGITAL_OCEAN_CLUSTER_ID="74b5ee91-5eaa-4d06-bad3-aaebae37b71f" \
  --set enabledFeatures.disableDryRun=true \
  --namespace maintenance --create-namespace