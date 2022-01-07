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

provider "google" {}

provider "google-beta" {}

provider "random" {}

variable "project_id" {
  type        = string
  description = "Google Cloud Project ID"
  default     = "OVERRIDE_DEFAULT_VALUE_WITH_YOUR_PROJECT_ID"
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

resource "google_compute_instance" "default" {
  project      = var.project_id
  name         = random_pet.machine_name.id
  machine_type = "e2-medium"
  zone         = "us-central1-a"
  tags         = ["yoshifumi-sample"]
  boot_disk {
    initialize_params {
      image = "projects/cos-cloud/global/images/cos-stable-93-16623-39-30"
    }
  }
  network_interface {
    network = "default"
    access_config {}
  }
  metadata = {
    # TODO: add container description here
    gce-container-declaration = <<EOF
    spec:
      containers:
        - name: ${local.svc_name}
          image: ${local.image_name}
          stdin: false
          tty: false
          restartPolicy: Always
    EOF
  }
  service_account {
    email  = google_service_account.default.email
    scopes = ["cloud-platform"]
  }
  depends_on = [null_resource.container]
}
