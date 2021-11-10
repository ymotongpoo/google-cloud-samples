// Copyright 2021 Google LLC
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
	"fmt"
	"log"
	"math"
	"net/http"
	"sync"
	"time"

	mexporter "github.com/GoogleCloudPlatform/opentelemetry-operations-go/exporter/metric"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/sdk/metric/controller/basic"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
)

const (
	magnifier   = 10
	accelerator = 1000.0
)

type waveObserveFloat struct {
	mu  sync.Mutex
	sin float64
	cos float64
}

func (wf *waveObserveFloat) set(sin, cos float64) {
	wf.mu.Lock()
	defer wf.mu.Unlock()
	wf.sin = sin
	wf.cos = cos
}

func (wf *waveObserveFloat) getSin() float64 {
	wf.mu.Lock()
	defer wf.mu.Unlock()
	return wf.sin
}

func (wf *waveObserveFloat) getCos() float64 {
	wf.mu.Lock()
	defer wf.mu.Unlock()
	return wf.cos
}

func newWaveObservedFloat(sin, cos float64) *waveObserveFloat {
	return &waveObserveFloat{
		sin: sin,
		cos: cos,
	}
}

func sin(m float64, v float64) float64 {
	return m * math.Sin(v)
}

func cos(m float64, v float64) float64 {
	return m * math.Cos(v)
}

var (
	// sin and cos wave observers
	wf *waveObserveFloat

	// monotonic incr counter
	c metric.Int64Counter

	// monotonic request counter
	req metric.Int64Counter
)

func init() {
	wf = newWaveObservedFloat(1.0*magnifier, 0.0*magnifier)
}

func main() {
	opts := []mexporter.Option{
		mexporter.WithProjectID("development-215403"),
		mexporter.WithInterval(10 * time.Second),
	}
	resOpt := basic.WithResource(resource.NewWithAttributes(
		semconv.SchemaURL,
		attribute.String("runtime", "cloud-run"),
		attribute.String("language", "go"),
	))
	pusher, err := mexporter.InstallNewPipeline(opts, resOpt)
	if err != nil {
		log.Fatalf("Failed to establish pipeline: %v", err)
	}
	ctx := context.Background()
	defer pusher.Stop(ctx)
	meter := pusher.Meter("cloudmonitoring/cloudrun")
	sinCallback := func(_ context.Context, result metric.Float64ObserverResult) {
		sin := wf.getSin()
		result.Observe(sin)
	}
	cosCallback := func(_ context.Context, result metric.Float64ObserverResult) {
		cos := wf.getCos()
		result.Observe(cos)
	}
	metric.Must(meter).NewFloat64GaugeObserver("wave_sin", sinCallback)
	metric.Must(meter).NewFloat64GaugeObserver("wave_cos", cosCallback)

	c = metric.Must(meter).NewInt64Counter("simple_counter")
	req = metric.Must(meter).NewInt64Counter("simple_request")
	go recordWave(wf)
	go recordCounter(ctx, c)

	http.HandleFunc("/healthz", healthzHandler)
	http.HandleFunc("/", mainHandler)
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal(err)
	}
}

func recordWave(wf *waveObserveFloat) {
	t := time.NewTicker(1 * time.Second)
	for range t.C {
		now := time.Now().Unix()
		n := now - (now / accelerator * accelerator)
		x := float64(n) / float64(accelerator)
		wf.set(sin(magnifier, x), cos(magnifier, x))
	}
}

func recordCounter(ctx context.Context, c metric.Int64Counter) {
	t := time.NewTicker(1 * time.Second)
	for range t.C {
		c.Add(ctx, 1)
	}
}

func mainHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	sin, cos := wf.getSin(), wf.getCos()
	req.Add(context.Background(), 1)
	w.Write([]byte(fmt.Sprintf("sin: %v, cos: %v", sin, cos)))
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}
