
variable "credentials" { }
variable "project" { }
variable "region" { }
variable "zone" { }
variable "machine_type" { }
variable "service_account_email" { }
variable "tls_key_file" {
  default = "key-xip.pem"
}
variable "tls_crt_file" {
  default = "cert-xip.pem"
}


#####################################################################

provider "google" {
  credentials = "${file("${var.credentials}")}"
  project     = "${var.project}"
  region      = "${var.region}"
  zone        = "${var.zone}"
}

resource "google_compute_instance" "rancher" {
  count = 3
  name         = "rancher${count.index + 1}"
  machine_type = "${var.machine_type}"
  zone         = "${var.zone}"

#  tags = ["foo", "bar"]

  boot_disk {
    initialize_params {
      image = "centos-7-v20180611"
      size  = "100"
    }
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP
    }
  }

  metadata_startup_script = <<SCRIPT
  sudo sh -c "echo 'exclude=docker-ce-selinux-18* docker-ce-18* docker-ce-selinux-17.12* docker-ce-17.12* docker-ce-selinux-17.09* docker-ce-17.09* docker-ce-selinux-17.06* docker-ce-17.06* ' >> /etc/yum.conf"
  sudo yum -y install epel-release
  sudo yum -y install yum-utils
  sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  sudo yum -y install docker-ce-selinux-17.03.0.ce-1.el7.centos
  sudo yum -y install docker-ce-17.03.2.ce-1.el7.centos
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -G docker rancher
  sudo sh -c 'cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF'
  sudo yum install -y kubectl
  SCRIPT

  service_account {
    email = "${var.service_account_email}"
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_instance_group" "rancher-servers" {
  name        = "rancher-servers"
  description = "Rancher HA cluster"

  instances = [
    "${google_compute_instance.rancher.*.self_link}"
  ]

  named_port {
    name = "http"
    port = "80"
  }

  named_port {
    name = "https"
    port = "443"
  }

  zone = "us-west1-a"
}

module "gce-lb-http" {
  source            = "gcp-modules/terraform-google-lb-http"
  name              = "rancher-http-lb"
  target_tags       = []
  ssl               = true
  private_key       = "${ file(var.tls_key_file) }"
  certificate       = "${ file(var.tls_crt_file) }"
  backends          = {
    "0" = [
      { group = "${google_compute_instance_group.rancher-servers.self_link}" },
    ],
  }
  backend_params    = [
    # health check path, port name, port number, timeout seconds.
    "/healthz,http,80,10",
  ]
}

resource "null_resource" "ssh" {
  depends_on = ["module.gce-lb-http"]
  count = 3

  triggers {
    instance_ips = "${join(",", google_compute_instance.rancher.*.network_interface.0.address)}"
  }

  connection {
    host = "${element(google_compute_instance.rancher.*.network_interface.0.access_config.0.assigned_nat_ip, count.index)}"
    user = "paul"
  }

  provisioner "file" {
    source      = "~/.ssh/gcp-rancher"
    destination = "~/id_rsa"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv ~/id_rsa /home/rancher/.ssh/",
      "sudo chown rancher /home/rancher/.ssh/id_rsa",
      "sudo chmod go-r /home/rancher/.ssh/id_rsa",
    ]
  }
}

resource "null_resource" "rke" {
  depends_on = ["null_resource.ssh"]
  count = 1

  connection {
    host = "${google_compute_instance.rancher.0.network_interface.0.access_config.0.assigned_nat_ip}"
    user = "paul"
  }

  provisioner "file" {
    content = "${data.template_file.rke-config.rendered}"
    destination = "~/cluster.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo su rancher -c 'curl -L https://github.com/rancher/rke/releases/download/v0.1.7/rke_linux-amd64 > /home/rancher/rke'",
      "sudo chmod u+x /home/rancher/rke",
      "sudo mv ~/cluster.yml /home/rancher/",
      "sudo chown rancher /home/rancher/cluster.yml",
      "sudo su rancher -c 'cd /home/rancher && ./rke up'",
      "sudo su rancher -c 'mkdir ~/.kube'",
      "sudo su rancher -c 'cp ~/kube_config_cluster.yml ~/.kube/config'",
    ]
  }
}

#####################################################################
output "ip" {
  value = [ "${ google_compute_instance.rancher.*.network_interface }" ]
}

output "console_url" {
  value = [ "https://rancher.${module.gce-lb-http.external_ip}.xip.io"]
}
