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
  }
}

provider "google" {}

provider "random" {}

variable "project_id" {
  description = "Google Cloud Project ID"
  default     = "OVERRIDE_DEFAULT_VALUE_WITH_YOUR_PROJECT_ID"
}

resource "random_pet" "machine_name" {
  length    = 2
  separator = "-"
}

resource "google_service_account" "default" {
  account_id   = "gce-docker-logging-sample"
  display_name = "GCE Docker Logging Sample"
}

resource "google_compute_instance" "default" {
  project      = var.project_id
  name         = random_pet.machine_name.value
  machine_type = "e2-medium"
  zone         = "us-central1-a"
  tags         = ["yoshifumi-sample"]
  boot_disk {
    initialize_params {
      image = "projects/cos-cloud/global/iamges/cos-stable-93-16623-39-30"
    }
  }
  network_interface {
    network = "default"
    acess_config {}
  }
  metadata = {
    # TODO: add container description here
    gce-container-declaration = <<EOF
    EOF
  }
  service_account {
    email  = google_service_account.default.email
    scopes = ["cloud-platform"]
  }
}
