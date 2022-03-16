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

package main

import (
	"context"
	"io"
	"log"
	"net/http/httptrace"
	"os"
	"time"

	cloudtrace "github.com/GoogleCloudPlatform/opentelemetry-operations-go/exporter/trace"
	"go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/jaeger"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	tracesdk "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
	"go.opentelemetry.io/otel/trace"
)

const (
	url      = "http://localhost:14268/api/traces"
	endpoint = "http://localhost:3333"
)

func main() {
	// 1a. create Jaeger exporter
	exporter, err := jaeger.New(jaeger.WithCollectorEndpoint(jaeger.WithEndpoint(url)))
	if err != nil {
		panic(err)
	}
	// 2a. create a new SpanProcessor with the exporter
	bsp := tracesdk.NewBatchSpanProcessor(exporter)

	// 1b. create Cloud Trace exporter
	projectID := os.Getenv("PROJECT_ID")
	log.Printf("Google Cloud Project: %s", projectID)
	ct, err := cloudtrace.New(cloudtrace.WithProjectID(projectID))
	if err != nil {
		panic(err)
	}
	// 2b. create a new SpanProcessor with the exporter
	ctbsp := tracesdk.NewBatchSpanProcessor(ct)

	// 3. create a TracerProvider with the SpanProcessor
	// along with some other configurations.
	tp := tracesdk.NewTracerProvider(
		tracesdk.WithSampler(tracesdk.AlwaysSample()),
		tracesdk.WithSpanProcessor(bsp),
		tracesdk.WithSpanProcessor(ctbsp),
		tracesdk.WithResource(resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceNameKey.String("client"),
		)),
	)

	// 4. register TP to global
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.TraceContext{})

	commonLabels := []attribute.KeyValue{
		attribute.String("environment", "demo"),
	}

	// 5. get a Tracer from the TP
	ctx := context.Background()
	tracer := otel.GetTracerProvider().Tracer("client")

	func(ctx context.Context) {
		// 6. create a root Span
		ctx, span := tracer.Start(
			ctx,
			"client-root",
			trace.WithAttributes(commonLabels...))
		log.Printf("client-root: %s", span.SpanContext().TraceID())
		defer span.End()

		// 7. create child span inside root span.
		// Be careful on which context is passed to the method.
		_, childSpan := tracer.Start(ctx, "client-child")
		defer childSpan.End()
		log.Printf("client-child: %s", childSpan.SpanContext().TraceID())

		// 8. make HTTP GET call with the custom HTTP client.
		ctx = httptrace.WithClientTrace(ctx, otelhttptrace.NewClientTrace(ctx))
		resp, err := otelhttp.Get(ctx, endpoint)
		if err != nil {
			log.Fatalf("failed to call: %v", err)
		}
		data, _ := io.ReadAll(resp.Body)
		log.Printf("Response: %v", string(data))

		<-time.After(time.Duration(100 * time.Millisecond))
	}(ctx)

	tp.ForceFlush(ctx)
	<-time.After(2 * time.Second)
}
