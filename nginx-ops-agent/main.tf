# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }
  }
}

# The service account used here is "roles/owner" for the project
provider "google" {
  credentials = file("${var.credentaial_key_path}")
}

provider "random" {}

variable "project_id" {
  type        = string
  description = "Google Cloud Project ID"
  default     = "OVERRIDE_DEFAULT_VALUE_WITH_YOUR_PROJECT_ID"
}

variable "credentaial_key_path" {
  type        = string
  description = "Path to the JSON key file for the Google Cloud service account"
  default     = "OVERRIDE_DEFAULT_VALUE_WITH_YOUR_CREDENTIAL_KEY_PATH"
}

variable "zone" {
  type        = string
  description = "Default compute zone in Google Cloud"
  default     = "us-central1-a"
}

locals {
  required_services = [
    "iam",
    "compute",
    "logging",
    "monitoring",
  ]

  required_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/compute.instanceAdmin",
    "roles/compute.osLogin",
  ]
}

resource "random_pet" "machine_name" {
  length    = 2
  separator = "-"
}

resource "google_service_account" "default" {
  project      = var.project_id
  account_id   = "nginx-ops-agent-sample"
  display_name = "Nginx + Ops Agent Sample"
}

resource "google_project_service" "required_service" {
  project            = var.project_id
  for_each           = toset(local.required_services)
  service            = "${each.value}.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_iam_member" "default" {
  project    = var.project_id
  for_each   = toset(local.required_roles)
  role       = each.value
  member     = "serviceAccount:${google_service_account.default.email}"
  depends_on = [google_project_service.required_service]
}

locals {
  server_tag = "allow-http-server"
}

resource "google_compute_firewall" "http" {
  name    = local.server_tag
  project = var.project_id
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_tags = [local.server_tag]
  target_tags = [local.server_tag]
}

resource "google_compute_instance" "default" {
  project      = var.project_id
  name         = random_pet.machine_name.id
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = [local.server_tag]
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }
  network_interface {
    network = "default"
    access_config {}
  }
  metadata = {
    user-data = file("./cloud-init.yaml")
  }
  service_account {
    email = google_service_account.default.email
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/pubsub",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append"
    ]
  }
  depends_on = [
    google_project_service.required_service,
    google_project_iam_member.default,
    google_compute_firewall.http,
  ]
}

# Add uptime check to trigger status request connection
resource "google_monitoring_uptime_check_config" "default" {
  project      = var.project_id
  display_name = "NGINX Uptime Check"
  timeout      = "10s"
  period       = "60s"
  http_check {
    path           = "/status"
    port           = "80"
    request_method = "GET"
  }
  monitored_resource {
    type = "gce_instance"
    labels = {
      project_id  = var.project_id
      instance_id = google_compute_instance.default.instance_id,
      zone        = google_compute_instance.default.zone,
    }
  }
  depends_on = [
    google_project_service.required_service,
    google_compute_instance.default
  ]
}

# Create a dedicated dashboard for NGINX monitoring
resource "google_monitoring_dashboard" "nginx-dash" {
  project        = var.project_id
  dashboard_json = file("./dashboard.json")
  depends_on     = [google_project_service.required_service]
}

# Create a uptime check for the NGINX instance
