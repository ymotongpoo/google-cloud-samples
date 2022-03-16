# Copyright 2022 Yoshi Yamaguchi
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

import os
import time

import flask
from opentelemetry import trace
from opentelemetry.exporter.cloud_trace import CloudTraceSpanExporter
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace.span import format_trace_id

# 1. register app to the auto instrumentor
app = flask.Flask(__name__)
FlaskInstrumentor().instrument_app(app)

def init() -> None:
    # 2a. create an Jaeger exporter object
    exporter = JaegerExporter(
        agent_host_name="localhost",
        agent_port=6831,
    )
    # 3a. create a SpanProcessor with the Jaeger exporter
    sp = BatchSpanProcessor(exporter)

    # 2b. create a Cloud Trace exporter object
    project_id = os.environ.get('PROJECT_ID', 'default')
    ctexporter = CloudTraceSpanExporter(
        project_id=project_id,
    )
    # 3b. create a SpanProcessor with the Cloud Trace exporter
    ctsp = BatchSpanProcessor(ctexporter)

    # 4. initialize TracerProvider
    tp = TracerProvider(
        resource=Resource.create({
            SERVICE_NAME: "server",
        })
    )
    tp.add_span_processor(sp)
    tp.add_span_processor(ctsp)
    # 5. register the TP to global
    trace.set_tracer_provider(tp)


@app.route("/", methods=["GET"])
def root() -> str:
    #
    # be aware that root handler is not instrumeted with root span
    #
    # 6. manual instrumentation can live with auto instrumentor
    tracer = trace.get_tracer(__name__)
    with tracer.start_as_current_span("server-childspan") as child_span:
        time.sleep(0.1)
        child_span.set_attribute("environment", "demo")
        ctx = child_span.get_span_context()
        trace_id = format_trace_id(ctx.trace_id)
        return f"server-child: {trace_id}"


def main(args=None) -> None:
    init()
    app.run(host="0.0.0.0", port=3333, debug=True)


if __name__ == "__main__":
    main()
