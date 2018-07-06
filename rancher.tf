
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
  yum install -y yum-utils
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  yum -y install docker-ce-selinux-17.03.0.ce-1.el7.centos
  yum -y install docker-ce-17.03.2.ce-1.el7.centos
  systemctl enable docker
  systemctl start docker
  curl -L https://github.com/rancher/rke/releases/download/v0.1.7/rke_linux-amd64 > /home/rancher/rke
  chown rancher /home/rancher/rke
  chmod u+x /home/rancher/rke
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

  connection {
    host = "${element(google_compute_instance.rancher.*.network_interface.0.access_config.0.assigned_nat_ip, count.index)}"
    user = "paul"
  }

  provisioner "file" {
    source      = "~/.ssh/gcp-root"
    destination = "~/id_rsa"
  }

  provisioner "file" {
    content = "${data.template_file.rke-config.rendered}"
    destination = "~/rke-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv ~/id_rsa /home/rancher/.ssh/",
      "sudo chown rancher /home/rancher/.ssh/id_rsa",
      "sudo mv ~/rke-config.yaml /home/rancher/",
      "sudo sh -c '/home/rancher/rke > /home/rancher/output.txt'",
    ]
  }

}

#####################################################################
output "ip" {
  value = [ "${ google_compute_instance.rancher.*.network_interface }" ]
}
