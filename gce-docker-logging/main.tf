// Copyright 2022 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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

provider "google" {
  credentials = file("${var.credentaial_key_path}")
}

provider "google-beta" {
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
  region = join("-", slice(split("-", var.zone), 0, 2))
}

resource "random_pet" "machine_name" {
  length    = 2
  separator = "-"
}

resource "google_service_account" "default" {
  project      = var.project_id
  account_id   = "gce-docker-logging-sample"
  display_name = "GCE Docker Logging Sample"
}

locals {
  enable_services = [
    "iam",
    "compute",
    "artifactregistry",
    "logging",
  ]
}

resource "google_project_service" "required_service" {
  project            = var.project_id
  for_each           = toset(local.enable_services)
  service            = "${each.value}.googleapis.com"
  disable_on_destroy = false
}
resource "google_artifact_registry_repository" "default" {
  provider      = google-beta
  project       = var.project_id
  location      = local.region
  repository_id = "sample-${random_pet.machine_name.id}"
  description   = "A repository for sample application"
  format        = "DOCKER"
  depends_on    = [google_project_service.required_service]
}

resource "google_artifact_registry_repository_iam_member" "registry" {
  provider   = google-beta
  project    = var.project_id
  location   = google_artifact_registry_repository.default.location
  repository = google_artifact_registry_repository.default.name
  role       = "roles/artifactregistry.repoAdmin"
  member     = "serviceAccount:${google_service_account.default.email}"
  depends_on = [google_project_service.required_service]
}

locals {
  required_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/compute.osLogin",
  ]
}

resource "google_project_iam_member" "default" {
  project  = var.project_id
  for_each = toset(local.required_roles)
  role     = each.value
  member   = "serviceAccount:${google_service_account.default.email}"
}


locals {
  paths         = split("/", google_artifact_registry_repository.default.id)
  registry      = format("%s-docker.pkg.dev", local.paths[3])
  registry_path = format("%s/%s/%s", local.registry, local.paths[1], local.paths[5])
  svc_name      = "log-sample"
  image_name    = "${local.registry_path}/${local.svc_name}:latest"
}

resource "null_resource" "container" {
  provisioner "local-exec" {
    command = <<-EOT
      docker build -t ${local.image_name} .
      docker push ${local.image_name}
    EOT
  }
  depends_on = [
    google_artifact_registry_repository.default,
    google_artifact_registry_repository_iam_member.registry,
  ]
}

module "gce-container" {
  source  = "terraform-google-modules/container-vm/google"
  version = "~> 2.0"

  container = {
    image = local.image_name
    tty   = false
    stdin = false
  }
  restart_policy = "Always"
}

resource "google_compute_instance" "default" {
  project      = var.project_id
  name         = random_pet.machine_name.id
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["yoshifumi-sample"]
  boot_disk {
    initialize_params {
      image = "projects/cos-cloud/global/images/cos-stable-93-16623-39-40"
    }
  }
  labels = {
    "container-vm" : "cos-stable-93-16623-39-40"
  }
  network_interface {
    network = "default"
    access_config {}
  }
  metadata = {
    gce-container-declaration = module.gce-container.metadata_value
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
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
  depends_on = [null_resource.container]
}
