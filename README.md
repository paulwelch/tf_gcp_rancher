# tf_gcp_rancher
Terraform module to provision a Rancher 2.0 HA Cluster on Google Cloud Platform

- **NOTE:** This module provisions paid resources on [Google Cloud Platform](https://cloud.google.com/) - you will be responsible for any usage fees incurred.

- **NOTE:** Remember to immediately go to the web console, **set the admin password** and complete the Rancher configuration.


### Description
- Creates a 3-node cluster with external L7 load balancer, per Rancher 2.0 [Installation Outline](https://rancher.com/docs/rancher/v2.x/en/installation/ha-server-install-external-lb/)
- Tested with self-signed cert and xip.io, but should work with CA issued cert also with additional DNS configuration
- Provisioning Users & Access
  - Provisioning user
    - User 'ssh_user' defined in variables
    - Executes provisioning steps
    - Terraform assumes ssh (key auth) access configured to the provisioned machines from where Terraform runs
    - Tested with provisioning users and keys defined in [gce metadata](https://cloud.google.com/compute/docs/instances/adding-removing-ssh-keys), however production environments should have a more sophisticated key management approach
    - *Requires sudo permission*
  - 'rancher' user
    - This module assumes a user named 'rancher' will exist on provisioned machines (in my case, created by gce metadata configuration)
    - Executes cluster install steps
    - Requires ssh (key auth) access to all other machine instances - configured by this module using keys defined in variables
    - Added to the docker group for docker permissions
    - *Does not require sudo permission*
- Cluster install is executed from the first machine provisioned, hostname 'rancher1'
- kubectl is configured for user 'rancher' on the first machine provisioned, hostname 'rancher1'  
- [Rancher 2.0 Documentation](https://rancher.com/docs/rancher/v2.x/en/)

### Input Variables

* ssh_user - linux user used for shell commands during provisioning
  * user must have ssh key authentication to machine instances
  * user must have sudo permission
* public_key_file - ssh public key filename
* private_key_file - ssh private key filename
* credentials - gcp credentials json filename
* project - gcp project id
* region - gcp region id
* zone - gcp zone id
* service_account_email - gcp service account email
* machine_type - gce machine type for rancher instances
  * [recommended size](https://rancher.com/docs/rancher/v2.x/en/installation/ha-server-install-external-lb/#1-provision-linux-hosts) for small production cluster is n1-standard-2
* tls_key_file - SSL key filename for gcp load balancer
* tls_crt_file - SSL cert filename for gcp load balancer
* tls_key_base64 - [base64 encoded key](https://rancher.com/docs/rancher/v2.x/en/installation/ha-server-install-external-lb/#7-configure-certificates) for Rancher Kubernetes Engine
* tls_crt_base64 - [base64 encoded cert](https://rancher.com/docs/rancher/v2.x/en/installation/ha-server-install-external-lb/#7-configure-certificates) for Rancher Kubernetes Engine
