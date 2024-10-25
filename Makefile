DATE := $(shell date +%FT%T%Z)
# argocd admin password set to: admin
# below is the escaped version of the password coming from: htpasswd -bnBC 10 "" admin | tr -d ':\n' | sed 's/$2y/$2a/'
ADMIN_PASSWORD := $$2a$$10$$fHMjO5gJhVg1fSU/lUwubO96tr4OiaKp9TdHTAjYm4z8eIfLNJOgK # admin
WEBHOOK_POD := $(shell kubectl -n argo-events get pod -l eventsource-name=webhook -o name)
CLUSTER_NAME := lab

build-cluster:
	kind create cluster --name $(CLUSTER_NAME) --config ./config/kind-cluster.yaml

build-cluster-linux:
	systemd-run --scope --user -p "Delegate=yes" kind create cluster --name $(CLUSTER_NAME) --config ./config/kind-cluster.yaml

delete-cluster:
	kind delete cluster	-n $(CLUSTER_NAME)

create-namespaces:
	kubectl create namespace argo
	kubectl create namespace argocd
	kubectl create namespace argo-events

argocd:
	kubectl apply -f ./charts/infra/argocd/install.yaml -n argocd
	# kubectl patch secret argocd-secret -n argocd -p '{"stringData": {"admin.password": "$(ADMIN_PASSWORD)", "admin.passwordMtime": "$(DATE)"}}'

argocd-patch-secret:
	kubectl patch secret argocd-secret -n argocd -p '{"stringData": {"admin.password": "$(ADMIN_PASSWORD)", "admin.passwordMtime": "$(DATE)"}}'

argocd-ui:
	kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=30s --timeout=60s
	open /Applications/Google\ Chrome.app/ "https://0.0.0.0:30080/applications"

argo-workflows:
	kubectl apply -f ./charts/infra/argo-workflows/install.yaml -n argo
	# bypass ui for login 
	kubectl patch deployment argo-server --namespace argo --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": [ "server", "--auth-mode=server" ]}]'

argo-workflows-ui:
	kubectl wait --for=condition=available deployment/argo-server -n argo --timeout=30s --timeout=60s
	open /Applications/Google\ Chrome.app/ "https://0.0.0.0:32746/workflows/undefined?&limit=50"

argocd-web-terminal:
	kubectl apply -f ./charts/crds/pod.yaml -n argocd

argo-events:
	kubectl apply -f ./charts/infra/argo-events/install.yaml -n argo-events
	kubectl apply -n argo-events -f ./charts/infra/argo-events/native.yaml
	kubectl apply -n argo-events -f ./charts/infra/argo-events/sensor-rbac.yaml
	kubectl apply -n argo-events -f ./charts/infra/argo-events/workflow-rbac.yaml

argocd-notifications:
	kubectl apply -n argocd -f ./charts/infra/argocd-notifications/install.yaml
	kubectl apply -n argocd -f ./charts/infra/argocd-triggers/install.yaml

ingress:
	kubectl apply -f ./charts/infra/nginx-ingress/deploy.yaml
	kubectl wait --namespace ingress-nginx \
  	--for=condition=ready pod \
  	--selector=app.kubernetes.io/component=controller \
  	--timeout=90s

demo-workflow:
	kubectl apply -n argo -f ./demo/workflow/install.yaml

yopass-install:
	#kubectl create namespace yopass
	#kubectl apply -n yopass -f ./charts/infra/yopass/deploy/yopass-k8.yaml
	kubectl apply -f ./charts/crds/yopass.yaml
	kubectl wait --for=condition=available deployment/yopass -n yopass --timeout=30s --timeout=60s
	kubectl port-forward service/yopass 1337:1337 -n yopass &

metrics-server:
	kubectl apply -f charts/crds/metrics-server.yaml -n argocd

webhook-tf:
	kubectl apply -n argo-events -f ./config/webhook-cm.yaml
	kubectl apply -n argo-events -f ./demo/webhook-tf/install.yaml
	kubectl wait -n argo-events --for=condition=ready pod -l eventsource-name=webhook
	# kubectl -n argo-events port-forward $(WEBHOOK_POD) 12000:12000 &

webhook-demo:
	curl -d '{"vControl":"bitbucket.org","repoOwner":"instadevelopers", "repo": "n1-iac","sha": "6051b943b22b04f7fe92b64e0c7694ea4832d0b1"}' -H "Content-Type: application/json" -X POST http://localhost:12000/tf

webhook-pod:
	kubectl apply -n argo-events -f ./demo/webhook-tf/pod.yaml

demo-dag:
	kubectl apply -n argo -f ./demo/dag/install.yaml

demo-cron:
	kubectl apply -n argocd -f ./charts/crds/cronflow.yaml
	# kubectl apply -n argo -f ./demo/cron/install.yaml

demo-webhook:
	kubectl apply -f ./demo/argoCDApps/webhook.yaml
	kubectl -n argo-events port-forward $(WEBHOOK_POD) 12000:12000 &

demo-webhook-run:
	curl -d '{"peanut-butter":"jelly time"}' -H "Content-Type: application/json" -X POST http://localhost:12000/example

web-pod:
	kubectl apply -f ./charts/crds/pod.yaml -n argocd

init: build-cluster create-namespaces argocd argocd-patch-secret argo-workflows argo-events 
init-basic: build-cluster create-namespaces argocd argocd-patch-secret 
init-linux: build-cluster-linux create-namespaces argocd argocd-patch-secret argo-workflows argo-events

hpa-noargo:
	kubectl create namespace hpa
	kubectl apply -f ./demo/hpa/php-apache.yaml -n hpa
	kubectl autoscale deployment php-apache -n hpa --cpu-percent=50 --min=1 --max=10

hpa-argo:
	kubectl apply -n argocd -f ./charts/crds/php-apache.yaml

hpa-loadgen:
	kubectl run -i --tty load-generator --rm -n php-apache --image=busybox:1.28 --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"

keda-install:
	kubectl apply -f charts/crds/keda.yaml -n argocd
	# kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.15.1/keda-2.15.1-core.yaml

localstack:
	kubectl apply -f charts/crds/localstack.yaml

localstack-portforward:
	kubectl -n localstack port-forward svc/localstack 4566:4566 &
# alias aws="aws --endpoint-url=http://localhost:4566"
# make aws calls as normal

psql-scaler:
	kubectl apply -f charts/crds/psql-scaler.yaml

sqs-scaler:
	kubectl apply -f charts/crds/php-apache-sqs.yaml

prometheus:
	kubectl apply -f charts/crds/prometheus.yaml
	kubectl wait --for=condition=available deployment/prometheus-server -n monitoring --timeout=30s --timeout=60s
	kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &


grafana:
	kubectl apply -f charts/crds/grafana.yaml
	kubectl wait --for=condition=available deployment/grafana -n monitoring --timeout=30s --timeout=60s
	kubectl port-forward -n monitoring svc/grafana 3000:80 &

http-metrics:
	kubectl apply -f charts/crds/prom-metrics.yaml
	kubectl wait --for=condition=available deployment/http-server -n prom --timeout=30s --timeout=60s
	kubectl port-forward -n prom svc/http-server 8090:80 &

rabbitmq-ns:
	kubectl create namespace rabbitmq

rabbitmq:
	kubectl apply -f charts/crds/rabbitMq.yaml
	kubectl wait --for=condition=available deployment/rmq -n rabbitmq --timeout=30s --timeout=60s
	kubectl port-forward -n rabbitmq svc/rmq-svc 8091:5672 &

rabbitmq-setup: init-basic argocd-ui metrics-server keda-install rabbitmq

rabbitmq-send: 
	./demo/rabbitMQ/sender/sender

rabbitmq-receive: 
	./demo/rabbitMQ/receiver/receiver
