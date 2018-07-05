variable "fqdn" { }

data "template_file" "rke-config" {

  template = <<EOF
nodes:
  - address: $${server1_addr} # hostname or IP to access nodes
    user: paul # root user (usually 'root')
    role: [controlplane,etcd,worker] # K8s roles for node
    ssh_key_path: ~/.ssh/id_rsa # path to PEM file
  - address: $${server1_addr}
    user: paul
    role: [controlplane,etcd,worker]
    ssh_key_path: ~/.ssh/id_rsa
  - address: $${server1_addr}
    user: paul
    role: [controlplane,etcd,worker]
    ssh_key_path: ~/.ssh/id_rsa

addons: |-
  ---
  kind: Namespace
  apiVersion: v1
  metadata:
    name: cattle-system
  ---
  kind: ServiceAccount
  apiVersion: v1
  metadata:
    name: cattle-admin
    namespace: cattle-system
  ---
  kind: ClusterRoleBinding
  apiVersion: rbac.authorization.k8s.io/v1
  metadata:
    name: cattle-crb
    namespace: cattle-system
  subjects:
  - kind: ServiceAccount
    name: cattle-admin
    namespace: cattle-system
  roleRef:
    kind: ClusterRole
    name: cluster-admin
    apiGroup: rbac.authorization.k8s.io
  ---
  apiVersion: v1
  kind: Secret
  metadata:
    name: cattle-keys-server
    namespace: cattle-system
  type: Opaque
  data:
    cacerts.pem: <BASE64_CA>  # CA cert used to sign cattle server cert and key
  ---
  apiVersion: v1
  kind: Service
  metadata:
    namespace: cattle-system
    name: cattle-service
    labels:
      app: cattle
  spec:
    ports:
    - port: 80
      targetPort: 80
      protocol: TCP
      name: http
    selector:
      app: cattle
  ---
  apiVersion: extensions/v1beta1
  kind: Ingress
  metadata:
    namespace: cattle-system
    name: cattle-ingress-http
    annotations:
      nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
      nginx.ingress.kubernetes.io/proxy-read-timeout: "1800"   # Max time in seconds for ws to remain shell window open
      nginx.ingress.kubernetes.io/proxy-send-timeout: "1800"   # Max time in seconds for ws to remain shell window open
      nginx.ingress.kubernetes.io/ssl-redirect: "false"        # Disable redirect to ssl
  spec:
    rules:
    - host: $${fqdn}
      http:
        paths:
        - backend:
            serviceName: cattle-service
            servicePort: 80
  ---
  kind: Deployment
  apiVersion: extensions/v1beta1
  metadata:
    namespace: cattle-system
    name: cattle
  spec:
    replicas: 1
    template:
      metadata:
        labels:
          app: cattle
      spec:
        serviceAccountName: cattle-admin
        containers:
        - image: rancher/rancher:latest
          imagePullPolicy: Always
          name: cattle-server
          ports:
          - containerPort: 80
            protocol: TCP
          volumeMounts:
          - mountPath: /etc/rancher/ssl
            name: cattle-keys-volume
            readOnly: true
        volumes:
        - name: cattle-keys-volume
          secret:
            defaultMode: 420
            secretName: cattle-keys-server
EOF

  vars {
    fqdn = "${var.fqdn}"
    #server1_addr = "${ google_compute_instance.rancher.*.network_interface.address }"
    #server2_addr = "${ google_compute_instance.rancher[2].network_interface.address }"
    #server3_addr = "${ google_compute_instance.rancher[3].network_interface.address }"
    server1_addr = ""
    server2_addr = ""
    server3_addr = ""
  }
}
