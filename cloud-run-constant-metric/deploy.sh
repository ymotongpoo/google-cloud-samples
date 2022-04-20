#!/bin/bash
#
# Copyright 2021 Google LLC
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

PROJECT_ID=$(gcloud config get-value project)
KO_DOCKER_REPO="gcr.io/${PROJECT_ID}/wave"
SERVICE="otel-always-on-metric"

if ! command -v ko &> /dev/null;
then
  echo "Install google/ko on your environment"
  echo "  https://github.com/google/ko"
  exit 1
fi

region=$(gcloud config get-value run/region)
if [ -z "${region}" ];
then
  echo "Cloud Run region is not set. Use default: asia-east1"
  region="asia-east1"
fi

existing=$(gcloud run services list --format="value(status.url)" --filter="metadata.name=${SERVICE}")
if [ $? -ne 0 ];
then
  echo "Failed to run 'gcloud run services list'"
  exit 1
fi

if [ -n "${existing}" ];
then
  echo "Service ${SERVICE} already exists. Delete it first."
  gcloud run services delete "${SERVICE}" --region="${region}" --quiet
fi

gcloud beta run deploy "${SERVICE}" \
--region="${region}" \
--image=$(ko publish ko://wave) \
--no-cpu-throttling \
--allow-unauthenticated \
--min-instances=1

gcloud run services list --format="value(status.url)" --filter="metadata.name=${SERVICE}"