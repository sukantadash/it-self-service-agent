oc new-project it-self-service-agent


# Set your namespace
export NAMESPACE=it-self-service-agent

oc exec -it deploy/self-service-agent-request-manager -n $NAMESPACE -- \
  python test/chat-responses-request-mgr.py \
  --user-id alice.johnson@company.com

# Set LLM configuration
export LLM=llama-4-scout-17b-16e-w4a16
export LLM_ID=llama-4-scout-17b-16e-w4a16
export LLM_API_TOKEN=
export LLM_URL=

# Set hugging face token, set to 1234 as not needed unless
# you want to use locally hosted LLM
export HF_TOKEN=1234


oc exec -it deploy/self-service-agent-request-manager -n $NAMESPACE -- \
  python test/chat-responses-request-mgr.py \
  --user-id alice.johnson@company.com