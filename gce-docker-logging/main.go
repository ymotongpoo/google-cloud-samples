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
	"fmt"
	"math/rand"
	"time"
)

func main() {
	t := time.NewTicker(time.Second)
	defer t.Stop()
	rand.Seed(time.Now().UnixNano())

	for range t.C {
		n := rand.Int31n(6) // the range of code of severity
		NewLogEntry(fmt.Sprintf("hello %d", n), Severity(n)).Print()
	}
}
