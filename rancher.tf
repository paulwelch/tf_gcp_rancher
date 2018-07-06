
variable "credentials" { }
variable "project" { }
variable "region" { }
variable "zone" { }
variable "machine_type" { }
variable "service_account_email" { }

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
  sudo yum install -y yum-utils
  sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  sudo yum -y install docker-ce-selinux-17.03.0.ce-1.el7.centos
  sudo yum -y install docker-ce-17.03.2.ce-1.el7.centos
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -G docker rancher
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

module "gce-ilb" {
  source         = "gcp-modules/terraform-google-lb-internal"
  region         = "${var.region}"
  name           = "rancher-ilb"
  ports          = ["80", "443"]
  health_port    = "80"
  source_tags    = []
  target_tags    = []
  backends       = [
    { group = "${google_compute_instance_group.rancher-servers.self_link}" },
  ]
}

resource "null_resource" "kube" {
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

  provisioner "file" {
    content = "${data.template_file.rke-config.rendered}"
    destination = "~/rke-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo sh -c 'curl -L https://github.com/rancher/rke/releases/download/v0.1.7/rke_linux-amd64 > /home/rancher/rke'",
      "sudo chown rancher /home/rancher/rke",
      "sudo chmod u+x /home/rancher/rke",
      "sudo mv ~/id_rsa /home/rancher/.ssh/",
      "sudo chown rancher /home/rancher/.ssh/id_rsa",
      "sudo chmod go-r /home/rancher/.ssh/id_rsa",
      "sudo mv ~/rke-config.yaml /home/rancher/",
      "sudo chown rancher /home/rancher/rke-config.yaml",
      "sudo sh -c '/home/rancher/rke > /home/rancher/output.txt'",
    ]
  }

}

#####################################################################
output "ip" {
  value = [ "${ google_compute_instance.rancher.*.network_interface }" ]
}
