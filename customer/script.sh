oc new-project it-self-service-agent


# Set your namespace
export NAMESPACE=it-self-service-agent


helm upgrade --install it-self-service-agent-sukanta ../helm -n $NAMESPACE -f ../helm/values-test.yaml

# -------------------------------------------------------------------
# Optional: persist `agent-service/config` on a PVC and sync config/docs
#
# 1) Enable PVC-backed config in your Helm values:
#    requestManagement:
#      agentService:
#        configPersistence:
#          enabled: true
#
# 2) Sync local config (including knowledge_bases/*.txt) into the PVC:
#    RELEASE=it-self-service-agent NAMESPACE=$NAMESPACE \
#      ./script-sync-agent-config-to-pvc.sh
#
# 3) Re-run ingestion manually (init job) to register/ingest the updated config:
#    RELEASE=it-self-service-agent NAMESPACE=$NAMESPACE \
#      ./script-run-ingestion-job.sh
#
# -------------------------------------------------------------------

helm upgrade --install it-self-service-agent ../helm -n $NAMESPACE -f values-test.yaml

2) Copy local config/docs to the PVC

./customer/script-run-ingestion-job.sh <namespace> <release> <valuesFile>


3) Run ingestion manually (recommended after every change)
./customer/script-run-ingestion-job.sh <namespace> <release> <valuesFile>

4) Check job + logs

oc get jobs -n $NAMESPACE | grep init
oc logs -n $NAMESPACE job/$(oc get jobs -n $NAMESPACE -o name | grep init | tail -n 1 | sed 's|job/||')

5) Test the agent

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