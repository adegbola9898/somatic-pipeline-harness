# Run Lifecycle

## Overview

Each pipeline execution is represented as a **Run**.

A run progresses through a defined set of states that describe its lifecycle.

## Run States

| State | Meaning | Terminal |
|------|------|------|
submitted | run accepted by API | no |
running | pipeline executing | no |
succeeded | pipeline completed successfully | yes |
failed | pipeline ended with error | yes |

## Lifecycle Flow

submitted  
→ running  
→ succeeded / failed

## Lifecycle Table

| Step | Actor | Action | State |
|-----|------|------|------|
1 | User | submits run | submitted |
2 | Backend API | records run metadata | submitted |
3 | Job launcher | starts Cloud Run Job | running |
4 | Cloud Run Job | executes pipeline | running |
5 | Cloud Run Job | writes outputs | running |
6 | Cloud Run Job | writes final state | succeeded / failed |

## Source of Truth

Run state is stored in **Firestore**.

Cloud Storage stores artifacts but does not define run state.
