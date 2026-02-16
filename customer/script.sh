oc new-project it-self-service-agent


# Set your namespace
export NAMESPACE=it-self-service-agent


#Build images manually
export IMAGE_TAG=0.0.1
./customer/script-images.sh

#build images from repo
export IMAGE_REPO=quay.io/rh-ai-quickstart
export IMAGE_TAG=0.0.1
export REPO_PUSH_SECRET_NAME=repo-push-secret
export DOCKERCONFIGJSON='{"auths":{"quay.io":{"auth":"<base64(username:token)>"}}}'
./customer/script-images-repo.sh

#build agent service image
oc start-build bc/ssa-agent-service -n $NAMESPACE --from-dir=. -F

oc rollout restart deploy/self-service-agent-agent-service -n $NAMESPACE

oc rollout status deploy/self-service-agent-agent-service -n $NAMESPACE


kubectl -n "$NAMESPACE" create secret generic self-service-agent-servicenow-credentials \
  --from-literal=servicenow-instance-url="http://self-service-agent-mock-servicenow:8080" \
  --from-literal=servicenow-api-key="now_mock_api_key" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" create secret generic pgvector \
  --from-literal=host="pgvector.llama-stack.svc.cluster.local" \
  --from-literal=port="5432" \
  --from-literal=dbname="pgvector" \
  --from-literal=user="pguser" \
  --from-literal=password="YOUR_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -


apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-it-self-service-agent-to-llama-stack
  namespace: llama-stack
spec:
  podSelector: {}   # applies to ALL pods in llama-stack namespace
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: it-self-service-agent


apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-llama-stack-to-it-self-service-agent
  namespace: it-self-service-agent
spec:
  podSelector: {}   # applies to ALL pods in it-self-service-agent namespace
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: llama-stack

#Apply below to both namespaces

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
spec:
  podSelector: {}   # all pods in llama-stack
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {} 

#verify
kubectl -n "$NAMESPACE" exec -it deploy/self-service-agent-request-manager -- \
  sh -lc 'curl -sS -m 5 http://llamastack-with-config-service.llama-stack.svc.cluster.local:8321/ || true'

kubectl delete job -l app.kubernetes.io/component=init -n "$NAMESPACE" --ignore-not-found
kubectl delete job -l app.kubernetes.io/name=self-service-agent -n "$NAMESPACE" --ignore-not-found

mv ./customer/mcp-servers-0.5.8.tgz ./helm/charts/

## comment the dependencies: in chart.yaml

helm upgrade --install self-service-agent helm -n $NAMESPACE -f ./customer/values-test.yaml

helm template self-service-agent helm -n $NAMESPACE -f ./customer/values-test.yaml


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

#evals
export NAMESPACE=it-self-service-agent
oc project $NAMESPACE
cd it-self-service-agent-sukanta/evaluations
uv venv
source .venv/bin/activate
uv sync
python run_conversations.py --reset-conversation