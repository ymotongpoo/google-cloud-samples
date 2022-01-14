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
	"bytes"
	"encoding/json"
	"fmt"
	"time"
)

type LogEntry struct {
	Timestamp time.Time `json:"timestamp"`
	Message   string    `json:"message"`
	Severity  Severity  `json:"severity"`
}

type Severity int

const (
	Default Severity = iota
	Debug
	Info
	Warn
	Error
	Fatal
)

func (s Severity) String() string {
	switch s {
	case Debug:
		return "DEBUG"
	case Info:
		return "INFO"
	case Warn:
		return "WARN"
	case Error:
		return "ERROR"
	case Fatal:
		return "FATAL"
	default:
		return "DEFAULT"
	}
}

func (s Severity) MarshalJSON() ([]byte, error) {
	buf := bytes.NewBufferString(`"`)
	buf.WriteString(s.String())
	buf.WriteString(`"`)
	return buf.Bytes(), nil
}

func NewLogEntry(msg string, s Severity) *LogEntry {
	return &LogEntry{
		Timestamp: time.Now(),
		Message:   msg,
		Severity:  s,
	}
}

func (e *LogEntry) String() (string, error) {
	bs, err := json.Marshal(e)
	if err != nil {
		return "", err
	}
	return string(bs), nil
}

func (e *LogEntry) Print() error {
	bs, err := e.String()
	if err != nil {
		return err
	}
	fmt.Println(bs)
	return nil
}
